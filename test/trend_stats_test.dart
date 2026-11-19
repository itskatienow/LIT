import 'package:flutter_test/flutter_test.dart';
import 'package:lit/data/trend_stats.dart';
import 'package:lit/models/app_settings.dart';
import 'package:lit/models/day_entry.dart';
import 'package:lit/util/dates.dart';

void main() {
  final start = DateTime(2026, 11, 1);

  Map<String, DayEntry> entries() => {
        dateKey(DateTime(2026, 11, 1)): const DayEntry(domperidoneTablets: 3, progesteroneTaken: true),
        dateKey(DateTime(2026, 11, 2)): const DayEntry(domperidoneTablets: 3),
        dateKey(DateTime(2026, 12, 15)): const DayEntry(pumped: true, pumpSessions: 6, outputMl: 100),
        dateKey(DateTime(2026, 12, 16)): const DayEntry(pumped: true, pumpSessions: 7, outputMl: 150),
        dateKey(DateTime(2026, 12, 20)):
            const DayEntry(pumped: true, pumpSessions: 8, outputMl: 200, powerPumped: true),
        // "Pumped" switched off: its saved details must not count.
        dateKey(DateTime(2026, 12, 21)): const DayEntry(pumped: false, pumpSessions: 5, outputMl: 999),
      };

  test('output, sessions and the latest 7-day average', () {
    final s = TrendStats.compute(
      settings: AppSettings(startDate: start),
      entries: entries(),
      today: DateTime(2026, 12, 21),
    );
    expect(s.totalOutputMl, 450);
    expect(s.daysWithOutput, 3);
    expect(s.highestDailyMl, 200);
    expect(s.highestDailyDate, DateTime(2026, 12, 20));
    expect(s.recentWindowStart, DateTime(2026, 12, 14));
    expect(s.recentWindowEnd, DateTime(2026, 12, 20));
    expect(s.recentDaysLogged, 3);
    expect(s.recentAverageMl, 150);
    expect(s.totalPumpSessions, 21);
    expect(s.powerPumpDays, 1);
  });

  test('7-day window excludes older days', () {
    final e = entries()..[dateKey(DateTime(2026, 12, 25))] = const DayEntry(pumped: true, outputMl: 300);
    final s = TrendStats.compute(settings: AppSettings(startDate: start), entries: e, today: DateTime(2026, 12, 25));
    // Window Dec 19–25: Dec 20 (200) and Dec 25 (300).
    expect(s.recentDaysLogged, 2);
    expect(s.recentAverageMl, 250);
  });

  test('domperidone inventory and supply projection', () {
    final s = TrendStats.compute(
      settings: AppSettings(startDate: start, domperidoneTablets: 100),
      entries: entries(),
      today: DateTime(2026, 12, 21), // Day 51: 8 tablets/day
    );
    expect(s.tabletsLoggedSinceCount, 6);
    expect(s.tabletsRemaining, 94);
    // 94 tablets at 8/day covers 11 days: Dec 21–31.
    expect(s.supplyLastsThrough, DateTime(2026, 12, 31));
  });

  test('tablet count date only subtracts tablets logged from that day on', () {
    final s = TrendStats.compute(
      settings: AppSettings(startDate: start, domperidoneTablets: 50, tabletCountDate: DateTime(2026, 11, 2)),
      entries: entries(),
      today: DateTime(2026, 11, 2),
    );
    expect(s.tabletsRemaining, 47);
  });

  test('no inventory without a tablet count', () {
    final s = TrendStats.compute(settings: AppSettings(startDate: start), entries: entries(), today: DateTime(2026, 12, 21));
    expect(s.tabletsRemaining, isNull);
  });

  test('adherence counts scheduled items from Day 1 to today', () {
    final s = TrendStats.compute(
      settings: AppSettings(startDate: start),
      entries: entries(),
      today: DateTime(2026, 11, 2), // Day 2
    );
    final dom = s.adherence.firstWhere((a) => a.label == 'Domperidone');
    expect(dom.scheduled, 6);
    expect(dom.logged, 6);
    final prog = s.adherence.firstWhere((a) => a.label == 'Progesterone');
    expect(prog.scheduled, 2);
    expect(prog.logged, 1);
    final est = s.adherence.firstWhere((a) => a.label == 'Estradiol');
    expect(est.scheduled, 1); // Sunday Nov 1
    expect(s.adherence.any((a) => a.label == 'Pumping'), isFalse);
  });

  test('settings round-trip through JSON', () {
    final settings = AppSettings(
      startDate: start,
      domperidoneTablets: 120,
      remindersEnabled: true,
      reminderKinds: const {},
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.startDate, start);
    expect(restored.domperidoneTablets, 120);
    expect(restored.remindersEnabled, isTrue);
    expect(restored.reminderKinds, isEmpty);
    expect(restored.times, settings.times);
  });
}
