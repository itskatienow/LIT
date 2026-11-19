import 'dart:collection';

import '../models/app_settings.dart';
import '../models/protocol.dart';
import '../util/dates.dart';

/// How far ahead reminders are scheduled. Opening LIT tops the window up.
const reminderHorizon = Duration(days: 7);

/// One notification: everything due at the same moment.
class ReminderSlot {
  const ReminderSlot({required this.at, required this.day, required this.events});

  final DateTime at;

  /// Protocol day the events belong to (overnight items count toward the
  /// evening before).
  final int day;
  final List<ScheduledEvent> events;

  String get title => events.map((e) => e.title).join(' + ');

  String get body =>
      'Day $day · ${Protocol.phaseForDay(day).label} phase — ${events.map((e) => e.detail).join(' · ')}';
}

/// Reminders due after [now] and within [horizon], soonest first. Items due at
/// the same moment (e.g. a 6 AM dose and a 6 AM pump) share one slot.
List<ReminderSlot> planReminders(
  AppSettings settings,
  DateTime now, {
  Duration horizon = reminderHorizon,
  int? limit,
}) {
  final start = settings.startDate;
  if (start == null || settings.reminderKinds.isEmpty) return const [];

  final end = now.add(horizon);
  final byMoment = SplayTreeMap<DateTime, List<({int day, ScheduledEvent event})>>();
  final today = dateOnly(now);
  // Start with yesterday: its midnight and 3–4 AM items fall on today's date.
  for (var i = -1; i <= horizon.inDays; i++) {
    final date = addDays(today, i);
    final day = Protocol.dayNumber(start, date)!;
    if (day < 1) continue;
    for (final event in Protocol.eventsFor(
      day: day,
      date: date,
      times: settings.times,
      estradiol: settings.estradiol,
      progesteroneMg: settings.progesteroneMg,
    )) {
      if (!settings.reminderKinds.contains(event.kind)) continue;
      final at = event.at(date);
      if (!at.isAfter(now) || at.isAfter(end)) continue;
      byMoment.putIfAbsent(at, () => []).add((day: day, event: event));
    }
  }

  final slots = [
    for (final entry in byMoment.entries)
      ReminderSlot(
        at: entry.key,
        day: entry.value.first.day,
        events: [for (final item in entry.value) item.event],
      ),
  ];
  return limit != null && slots.length > limit ? slots.sublist(0, limit) : slots;
}
