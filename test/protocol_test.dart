import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lit/models/app_settings.dart';
import 'package:lit/models/protocol.dart';
import 'package:lit/util/dates.dart';

void main() {
  // Sunday, Nov 1 2026 is Day 1.
  final start = DateTime(2026, 11, 1);
  DateTime dayDate(int day) => Protocol.dateForDay(start, day);

  group('day numbers and phases', () {
    test('start date is Day 1', () {
      expect(Protocol.dayNumber(start, start), 1);
      expect(Protocol.dayNumber(start, DateTime(2026, 12, 10)), 40);
      expect(Protocol.dayNumber(start, DateTime(2026, 10, 31)), 0);
      expect(Protocol.dayNumber(null, start), isNull);
    });

    test('Prime is 40 days, Switch 2, then Supply', () {
      expect(Protocol.phaseForDay(null), Phase.notStarted);
      expect(Protocol.phaseForDay(0), Phase.notStarted);
      expect(Protocol.phaseForDay(1), Phase.build);
      expect(Protocol.phaseForDay(40), Phase.build);
      expect(Protocol.phaseForDay(41), Phase.birth);
      expect(Protocol.phaseForDay(42), Phase.birth);
      expect(Protocol.phaseForDay(43), Phase.lactation);
      expect(Protocol.phaseForDay(400), Phase.lactation);
    });

    test('day counting ignores daylight-saving shifts', () {
      // US clocks spring forward on Mar 8 2026.
      expect(Protocol.dayNumber(DateTime(2026, 3, 1), DateTime(2026, 3, 9)), 9);
      expect(daysBetween(DateTime(2026, 10, 30), DateTime(2026, 11, 2)), 3);
    });

    test('key dates', () {
      expect(dayDate(Protocol.fullDomperidoneDay), DateTime(2026, 11, 15)); // 2 weeks out
      expect(dayDate(Protocol.lastProgesteroneDay), DateTime(2026, 12, 10));
      expect(dayDate(Protocol.pumpingStartDay), DateTime(2026, 12, 11));
      expect(dayDate(Protocol.powerPumpingStartDay), DateTime(2026, 12, 26));
    });
  });

  group('domperidone ramp-up', () {
    test('week 1: 10 mg at 6 AM, noon, 6 PM', () {
      final doses = Protocol.domperidoneDoses(1);
      expect(doses.map((d) => d.minuteOfDay), [6 * 60, 12 * 60, 18 * 60]);
      expect(doses.map((d) => d.mg), [10, 10, 10]);
      expect(Protocol.domperidoneTabletsForDay(7), 3);
    });

    test('week 2: 20 / 10 / 20 mg', () {
      expect(Protocol.domperidoneDoses(8).map((d) => d.mg), [20, 10, 20]);
      expect(Protocol.domperidoneTabletsForDay(14), 5);
      expect(Protocol.domperidoneMgForDay(14), 50);
    });

    test('from Day 15: 20 mg at 6 AM, noon, 6 PM and midnight', () {
      final doses = Protocol.domperidoneDoses(15);
      expect(doses.map((d) => d.minuteOfDay), [6 * 60, 12 * 60, 18 * 60, 24 * 60]);
      expect(Protocol.domperidoneTabletsForDay(15), 8);
      expect(Protocol.domperidoneMgForDay(100), 80);
    });

    test('nothing before Day 1', () {
      expect(Protocol.domperidoneDoses(0), isEmpty);
    });
  });

  group('estradiol', () {
    const plan = EstradiolPlan(); // the original protocol: 6 mg a week over 3 injections
    List<EstradiolSlot> slots(EstradiolPlan p, int day) => Protocol.estradiolSlots(day, dayDate(day), p);
    List<ScheduledEvent> estradiolEvents(EstradiolPlan p, int day) => Protocol.eventsFor(
          day: day,
          date: dayDate(day),
          estradiol: p,
        ).where((e) => e.kind == EventKind.estradiol).toList();

    test('default: 2 mg injections Wednesday AM, Friday PM, Sunday AM', () {
      expect(plan.injectionDoseMg, 2);
      expect(slots(plan, 4), [EstradiolSlot.morning]); // Wed
      expect(slots(plan, 6), [EstradiolSlot.evening]); // Fri
      expect(slots(plan, 8), [EstradiolSlot.morning]); // Sun
      expect(slots(plan, 2), isEmpty); // Mon
      expect(Protocol.estradiolSlots(0, DateTime(2026, 10, 31), plan), isEmpty); // before start
      expect(plan.injectionDaysLabel, 'Wed AM, Fri PM, Sun AM');
    });

    test('2 a week: Wednesday AM and Saturday PM; 1 a week: Wednesday AM', () {
      const two = EstradiolPlan(injectionsPerWeek: 2);
      expect(slots(two, 4), [EstradiolSlot.morning]); // Wed
      expect(slots(two, 7), [EstradiolSlot.evening]); // Sat
      expect(slots(two, 6), isEmpty); // Fri
      expect(slots(two, 8), isEmpty); // Sun
      expect(two.injectionDaysLabel, 'Wed AM, Sat PM');

      const one = EstradiolPlan(injectionsPerWeek: 1);
      expect([for (var day = 1; day <= 7; day++) ...slots(one, day)], [EstradiolSlot.morning]);
      expect(one.injectionDaysLabel, 'Wed AM');
    });

    test('injection dose: weekly ÷ injections, rounded up to the next 0.5 mg', () {
      double? dose(double weekly, int n) => EstradiolPlan(weeklyDoseMg: weekly, injectionsPerWeek: n).injectionDoseMg;
      expect(dose(5, 3), 2); // 1.67 → 2
      expect(dose(10, 3), 3.5); // 3.33 → 3.5
      expect(dose(6, 3), 2); // already a multiple of 0.5
      expect(dose(4.5, 3), 1.5);
      expect(dose(7, 2), 3.5);
      expect(dose(0.9, 3), 0.5);
      expect(dose(5, 1), 5);

      const fiveMg = EstradiolPlan(weeklyDoseMg: 5);
      expect(fiveMg.exactInjectionMg, closeTo(1.667, 0.001));
      expect(fiveMg.injectionRoundedUp, isTrue);
      expect(fiveMg.injectedPerWeekMg, 6);
      expect(plan.injectionRoundedUp, isFalse);
      expect(const EstradiolPlan(weeklyDoseMg: null).injectionDoseMg, isNull);
    });

    test('injection volume comes from the strength', () {
      const p = EstradiolPlan(weeklyDoseMg: 5, strengthMgPerMl: 5);
      expect(p.injectionVolumeMl, closeTo(0.4, 1e-9));
      expect(p.doseLabel, '2 mg · 0.4 mL');
      expect(plan.injectionVolumeMl, isNull);
      expect(plan.doseLabel, '2 mg');
      expect(const EstradiolPlan(strengthMgPerMl: 40).doseLabel, '2 mg · 0.05 mL');
      expect(const EstradiolPlan(strengthMgPerMl: 6).doseLabel, '2 mg · 0.333 mL');

      final friday = estradiolEvents(p, 6).single;
      expect(friday.title, 'Estradiol 2 mg');
      expect(friday.detail, 'Injection · 0.4 mL · evening');
      expect(friday.time, '8:00 PM');
    });

    test('oral: the daily dose once a day, in the morning', () {
      const oral = EstradiolPlan(method: EstradiolMethod.oral, dailyDoseMg: 4);
      for (var day = 1; day <= 7; day++) {
        expect(slots(oral, day), [EstradiolSlot.morning]);
      }
      final event = estradiolEvents(oral, 2).single;
      expect(event.title, 'Estradiol 4 mg');
      expect(event.detail, 'Oral');
      expect(event.time, '8:00 AM');
    });

    test('sublingual: half the daily dose, morning and evening', () {
      const sl = EstradiolPlan(method: EstradiolMethod.sublingual, dailyDoseMg: 3);
      expect(sl.doseMg, 1.5);
      final events = estradiolEvents(sl, 2);
      expect(events.map((e) => e.title), ['Estradiol 1.5 mg', 'Estradiol 1.5 mg']);
      expect(events.map((e) => e.detail), ['Sublingual · morning', 'Sublingual · evening']);
      expect(events.map((e) => e.time), ['8:00 AM', '8:00 PM']);
    });

    test('a dose that is not set yet still appears on the schedule', () {
      const oral = EstradiolPlan(method: EstradiolMethod.oral);
      expect(oral.doseMg, isNull);
      expect(oral.doseLabel, isNull);
      expect(estradiolEvents(oral, 2).single.title, 'Estradiol');
    });

    test('which schedule times each method uses', () {
      expect(plan.timeUsage(EstradiolSlot.morning), 'Wednesday & Sunday injections');
      expect(plan.timeUsage(EstradiolSlot.evening), 'Friday injection');
      expect(const EstradiolPlan(injectionsPerWeek: 1).timeUsage(EstradiolSlot.evening), isNull);
      const oral = EstradiolPlan(method: EstradiolMethod.oral);
      expect(oral.timeUsage(EstradiolSlot.morning), isNotNull);
      expect(oral.timeUsage(EstradiolSlot.evening), isNull);
      const sl = EstradiolPlan(method: EstradiolMethod.sublingual);
      expect(sl.timeUsage(EstradiolSlot.evening), isNotNull);
    });

    test('saved in settings; settings from before keep the original plan', () {
      const p = EstradiolPlan(
        method: EstradiolMethod.sublingual,
        weeklyDoseMg: null,
        injectionsPerWeek: 2,
        strengthMgPerMl: 40,
        dailyDoseMg: 2.5,
      );
      final json = jsonDecode(jsonEncode(AppSettings(estradiol: p).toJson())) as Map<String, dynamic>;
      expect(AppSettings.fromJson(json).estradiol, p);
      expect(AppSettings.fromJson(const {}).estradiol, plan);
      expect(EstradiolPlan.fromJson(const {'injectionsPerWeek': 7, 'method': 'patch'}).injectionsPerWeek, 3);
    });
  });

  group('progesterone', () {
    test('nightly through Day 40 only', () {
      expect(Protocol.progesteroneScheduled(1), isTrue);
      expect(Protocol.progesteroneScheduled(40), isTrue);
      expect(Protocol.progesteroneScheduled(41), isFalse);
    });

    test('the dose comes from Settings, 300 mg by default', () {
      ScheduledEvent progesterone(double? mg) => Protocol.eventsFor(day: 2, date: dayDate(2), progesteroneMg: mg)
          .firstWhere((e) => e.kind == EventKind.progesterone);
      expect(Protocol.eventsFor(day: 2, date: dayDate(2)).firstWhere((e) => e.kind == EventKind.progesterone).title,
          'Progesterone 300 mg');
      expect(progesterone(200).title, 'Progesterone 200 mg');
      expect(progesterone(100.5).title, 'Progesterone 100.5 mg');
      expect(progesterone(null).title, 'Progesterone');
    });

    test('dose is saved in settings; settings from before keep 300 mg', () {
      AppSettings roundTrip(AppSettings s) =>
          AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(const AppSettings().progesteroneMg, 300);
      expect(AppSettings.fromJson(const {}).progesteroneMg, 300);
      expect(roundTrip(const AppSettings(progesteroneMg: 200)).progesteroneMg, 200);
      expect(roundTrip(const AppSettings(progesteroneMg: null)).progesteroneMg, isNull); // cleared stays cleared
      expect(const AppSettings().reminderSignature, isNot(const AppSettings(progesteroneMg: 200).reminderSignature));
    });
  });

  group('daily schedule', () {
    test('Prime day has domperidone and progesterone, no pumping', () {
      final events = Protocol.eventsFor(day: 2, date: dayDate(2));
      expect(events.where((e) => e.kind == EventKind.domperidone), hasLength(3));
      expect(events.where((e) => e.kind == EventKind.progesterone), hasLength(1));
      expect(events.where((e) => e.kind == EventKind.pump), isEmpty);
    });

    test('pumping starts Day 41 with 8 sessions, overnight ones last', () {
      expect(Protocol.eventsFor(day: 40, date: dayDate(40)).where((e) => e.kind == EventKind.pump), isEmpty);
      final pumps = Protocol.eventsFor(day: 41, date: dayDate(41)).where((e) => e.kind == EventKind.pump).toList();
      expect(pumps, hasLength(8));
      expect(pumps.last.time, '3–4 AM');
      expect(pumps.last.at(dayDate(41)), DateTime(2026, 12, 12, 3));
      expect(pumps[6].time, 'Midnight');
    });

    test('power pumping is added on Day 56', () {
      bool hasPower(int day) =>
          Protocol.eventsFor(day: day, date: dayDate(day)).any((e) => e.kind == EventKind.powerPump);
      expect(hasPower(55), isFalse);
      expect(hasPower(56), isTrue);
    });

    test('custom times are used and events are sorted', () {
      const times = ReminderTimes(estradiolMorning: 7 * 60 + 30, progesterone: 21 * 60);
      final events = Protocol.eventsFor(day: 4, date: dayDate(4), times: times); // a Wednesday
      final estradiol = events.firstWhere((e) => e.kind == EventKind.estradiol);
      expect(estradiol.time, '7:30 AM');
      final minutes = events.map((e) => e.minuteOfDay).toList();
      expect(minutes, [...minutes]..sort());
    });
  });

  test('time labels', () {
    expect(formatMinuteOfDay(6 * 60), '6:00 AM');
    expect(formatMinuteOfDay(12 * 60), 'Noon');
    expect(formatMinuteOfDay(24 * 60), 'Midnight');
    expect(formatMinuteOfDay(18 * 60 + 5), '6:05 PM');
  });
}
