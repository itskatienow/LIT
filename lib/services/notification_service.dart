import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_settings.dart';
import '../models/protocol.dart';
import '../util/dates.dart';

class ReminderStatus {
  const ReminderStatus({
    this.supported = true,
    this.permissionGranted,
    this.exactAlarms = true,
    this.scheduledCount = 0,
    this.scheduledThrough,
    this.error,
  });

  final bool supported;

  /// Null until checked.
  final bool? permissionGranted;

  /// Android only: false means reminders may arrive a few minutes late.
  final bool exactAlarms;

  final int scheduledCount;
  final DateTime? scheduledThrough;
  final String? error;
}

/// Schedules local reminders for the protocol.
///
/// The OS only holds a limited number of pending notifications (64 on iOS),
/// so reminders are scheduled for a rolling window of upcoming days and
/// topped up whenever the app is opened or the settings change.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  final status = ValueNotifier<ReminderStatus>(const ReminderStatus());

  static const _testId = 999999;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'lit_reminders',
      'Reminders',
      channelDescription: 'Medication and pumping reminders',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get isSupported => _isAndroid || _isIOS;

  /// iOS keeps at most 64 pending notifications; Android allows many more
  /// (Samsung caps alarms at 500).
  int get _maxScheduled => _isIOS ? 60 : 200;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (!isSupported) {
      status.value = const ReminderStatus(supported: false);
      return;
    }
    try {
      tzdata.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (e) {
        // Times are converted from device-local DateTimes, so the scheduled
        // instants stay correct even if the zone name is unknown.
        debugPrint('LIT: could not resolve local time zone: $e');
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_lit'),
          iOS: DarwinInitializationSettings(
            // Asked for when the user turns reminders on, not at launch.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('LIT: notifications unavailable: $e');
      status.value = ReminderStatus(error: '$e');
    }
  }

  /// Shows the OS permission prompt. Call from a user action.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      if (_isAndroid) return await _android?.requestNotificationsPermission() ?? false;
      if (_isIOS) return await _ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('LIT: permission request failed: $e');
    }
    return false;
  }

  /// Android 12+: opens the system screen for "Alarms & reminders".
  Future<void> requestExactAlarms() async {
    if (!_ready || !_isAndroid) return;
    await _android?.requestExactAlarmsPermission();
  }

  Future<bool> _permissionGranted() async {
    if (_isAndroid) return await _android?.areNotificationsEnabled() ?? false;
    if (_isIOS) return (await _ios?.checkPermissions())?.isEnabled ?? false;
    return false;
  }

  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: _testId,
      title: 'LIT reminders are on',
      body: 'This is what your medication and pumping reminders will look like.',
      notificationDetails: _details,
    );
  }

  /// Cancels everything and schedules the upcoming window from [settings].
  Future<void> reschedule(AppSettings settings) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final granted = await _permissionGranted();
      final exact = _isAndroid ? (await _android?.canScheduleExactNotifications() ?? false) : true;

      final start = settings.startDate;
      if (!settings.remindersEnabled || start == null || settings.reminderKinds.isEmpty || !granted) {
        status.value = ReminderStatus(permissionGranted: granted, exactAlarms: exact);
        return;
      }

      // Group events by moment so e.g. a 6 AM dose and a 6 AM pump arrive as
      // one notification. Start from yesterday so its overnight items count.
      final now = DateTime.now();
      final base = dateOnly(now);
      final byMoment = SplayTreeMap<DateTime, List<({int day, ScheduledEvent event})>>();
      for (var i = -1; i <= 45 && byMoment.length < _maxScheduled; i++) {
        final date = addDays(base, i);
        final day = Protocol.dayNumber(start, date)!;
        if (day < 1) continue;
        for (final event in Protocol.eventsFor(day: day, date: date, times: settings.times)) {
          if (!settings.reminderKinds.contains(event.kind)) continue;
          final at = event.at(date);
          if (!at.isAfter(now)) continue;
          byMoment.putIfAbsent(at, () => []).add((day: day, event: event));
        }
      }

      var id = 0;
      DateTime? last;
      for (final slot in byMoment.entries.take(_maxScheduled)) {
        final day = slot.value.first.day;
        final events = slot.value.map((e) => e.event).toList();
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: tz.TZDateTime.from(slot.key, tz.local),
          notificationDetails: _details,
          androidScheduleMode:
              exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
          title: events.map((e) => e.title).join(' + '),
          body: _body(day, events),
        );
        last = slot.key;
      }

      status.value = ReminderStatus(
        permissionGranted: true,
        exactAlarms: exact,
        scheduledCount: id,
        scheduledThrough: last,
      );
    } catch (e) {
      debugPrint('LIT: scheduling failed: $e');
      status.value = ReminderStatus(error: '$e');
    }
  }

  String _body(int day, List<ScheduledEvent> events) {
    final phase = Protocol.phaseForDay(day).label;
    final details = events.map((e) => e.detail).join(' · ');
    return 'Day $day · $phase phase — $details';
  }
}
