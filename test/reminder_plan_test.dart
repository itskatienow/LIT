import 'package:flutter_test/flutter_test.dart';
import 'package:lit/models/app_settings.dart';
import 'package:lit/models/protocol.dart';
import 'package:lit/services/reminder_plan.dart';

void main() {
  // Sunday, Nov 1 2026 is Day 1, so Sunday, Dec 20 is Day 50 (Supply).
  final settings = AppSettings(startDate: DateTime(2026, 11, 1), remindersEnabled: true);

  test('covers only the next 7 days, soonest first', () {
    final now = DateTime(2026, 12, 20, 12, 30);
    final slots = planReminders(settings, now);

    expect(slots, isNotEmpty);
    expect(slots.first.at, DateTime(2026, 12, 20, 15));
    expect(slots.last.at, DateTime(2026, 12, 27, 12)); // last item before 12:30 a week later
    for (final s in slots) {
      expect(s.at.isAfter(now), isTrue);
      expect(s.at.isAfter(now.add(reminderHorizon)), isFalse);
    }
    final times = slots.map((s) => s.at).toList();
    expect(times, [...times]..sort());
    expect(times.toSet().length, times.length); // one slot per moment
  });

  test('groups items due at the same moment into one notification', () {
    final slots = planReminders(settings, DateTime(2026, 12, 20, 12, 30));
    final sixPm = slots.firstWhere((s) => s.at == DateTime(2026, 12, 20, 18));
    expect(sixPm.events.map((e) => e.kind), [EventKind.domperidone, EventKind.pump]);
    expect(sixPm.title, 'Domperidone 20 mg + Pump session');
    expect(sixPm.body, startsWith('Day 50 · Supply phase'));
  });

  test("includes yesterday's overnight items", () {
    final slots = planReminders(settings, DateTime(2026, 12, 20, 1));
    expect(slots.first.at, DateTime(2026, 12, 20, 3)); // Day 49's 3–4 AM pump
    expect(slots.first.day, 49);
  });

  test('respects the reminder types that are switched on', () {
    final onlyProgesterone = settings.copyWith(reminderKinds: {EventKind.progesterone});
    final slots = planReminders(onlyProgesterone, DateTime(2026, 11, 10, 12)); // Day 10
    expect(slots, hasLength(7)); // Nov 10–16 at 10 PM
    expect(slots.every((s) => s.title == 'Progesterone 300 mg'), isTrue);
  });

  test('starts at Day 1 when the protocol has not begun yet', () {
    final slots = planReminders(settings, DateTime(2026, 10, 28, 12));
    expect(slots.first.at, DateTime(2026, 11, 1, 6));
    expect(slots.first.day, 1);
  });

  test('nothing to plan without a start date or reminder types', () {
    expect(planReminders(const AppSettings(), DateTime(2026, 12, 20)), isEmpty);
    expect(planReminders(settings.copyWith(reminderKinds: {}), DateTime(2026, 12, 20)), isEmpty);
  });

  test('applies the safety limit', () {
    expect(planReminders(settings, DateTime(2026, 12, 20, 12, 30), limit: 5), hasLength(5));
  });
}
