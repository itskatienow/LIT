import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_settings.dart';
import 'reminder_plan.dart';

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
/// Reminders are scheduled for a rolling 7-day window ([reminderHorizon]) and
/// topped up whenever the app is opened or the settings change.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  final status = ValueNotifier<ReminderStatus>(const ReminderStatus());

  static const _testId = 999999;
  static const _scheduledTestId = 999998;

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

  /// Safety cap below the OS limits (iOS keeps 64 pending notifications;
  /// Samsung caps an app at 500 alarms). A 7-day window is ~70 at most.
  int get _maxScheduled => _isIOS ? 60 : 150;

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

  Future<bool> _exactAllowed() async =>
      _isAndroid ? (await _android?.canScheduleExactNotifications() ?? false) : true;

  static AndroidScheduleMode _mode(bool exact) =>
      exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;

  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: _testId,
      title: 'LIT reminders are on',
      body: 'This is what your medication and pumping reminders will look like.',
      notificationDetails: _details,
    );
  }

  /// When a scheduled test is pending, so rescheduling can keep it.
  DateTime? _scheduledTestAt;

  /// Schedules a test reminder through the same alarm path as real
  /// reminders. Lock the phone and wait to confirm delivery.
  Future<DateTime?> scheduleTest({Duration delay = const Duration(minutes: 1)}) async {
    if (!_ready) return null;
    final at = DateTime.now().add(delay);
    await _scheduleTestAt(at, await _exactAllowed());
    return at;
  }

  Future<void> _scheduleTestAt(DateTime at, bool exact) async {
    _scheduledTestAt = at;
    await _plugin.zonedSchedule(
      id: _scheduledTestId,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details,
      androidScheduleMode: _mode(exact),
      title: 'LIT test reminder',
      body: exact
          ? 'Scheduled reminders are working.'
          : 'Scheduled reminders are working, but without exact timing they may arrive late.',
    );
  }

  Future<void>? _running;
  AppSettings? _queued;

  /// Replaces pending reminders with the upcoming window from [settings].
  /// Calls made while one is running are coalesced into one more run.
  Future<void> reschedule(AppSettings settings) {
    _queued = settings;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_queued != null) {
      final next = _queued!;
      _queued = null;
      await _reschedule(next);
    }
  }

  Future<void> _reschedule(AppSettings settings) async {
    if (!_ready) return;
    try {
      // Pending only: reminders already showing in the tray stay put.
      await _plugin.cancelAllPendingNotifications();
      final granted = await _permissionGranted();
      final exact = await _exactAllowed();
      final testAt = _scheduledTestAt;
      if (testAt != null && testAt.isAfter(DateTime.now().add(const Duration(seconds: 2)))) {
        await _scheduleTestAt(testAt, exact);
      }

      final start = settings.startDate;
      if (!settings.remindersEnabled || start == null || settings.reminderKinds.isEmpty || !granted) {
        status.value = ReminderStatus(permissionGranted: granted, exactAlarms: exact);
        return;
      }

      final slots = planReminders(settings, DateTime.now(), limit: _maxScheduled);
      for (var id = 0; id < slots.length; id++) {
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: tz.TZDateTime.from(slots[id].at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: _mode(exact),
          title: slots[id].title,
          body: slots[id].body,
        );
      }

      status.value = ReminderStatus(
        permissionGranted: true,
        exactAlarms: exact,
        scheduledCount: slots.length,
        scheduledThrough: slots.isEmpty ? null : slots.last.at,
      );
    } catch (e) {
      debugPrint('LIT: scheduling failed: $e');
      status.value = ReminderStatus(error: '$e');
    }
  }
}
