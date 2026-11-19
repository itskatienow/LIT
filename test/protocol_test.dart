import 'package:flutter_test/flutter_test.dart';
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

    test('Build is 40 days, Birth 2, then Lactation', () {
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

  group('hormones', () {
    test('estradiol: Wednesday AM, Friday PM, Sunday AM', () {
      expect(Protocol.estradiolSlot(4, DateTime(2026, 11, 4)), EstradiolSlot.morning); // Wed
      expect(Protocol.estradiolSlot(6, DateTime(2026, 11, 6)), EstradiolSlot.evening); // Fri
      expect(Protocol.estradiolSlot(8, DateTime(2026, 11, 8)), EstradiolSlot.morning); // Sun
      expect(Protocol.estradiolSlot(2, DateTime(2026, 11, 2)), isNull); // Mon
      expect(Protocol.estradiolSlot(0, DateTime(2026, 10, 31)), isNull); // before start
    });

    test('progesterone nightly through Day 40 only', () {
      expect(Protocol.progesteroneScheduled(1), isTrue);
      expect(Protocol.progesteroneScheduled(40), isTrue);
      expect(Protocol.progesteroneScheduled(41), isFalse);
    });
  });

  group('daily schedule', () {
    test('Build day has domperidone and progesterone, no pumping', () {
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
