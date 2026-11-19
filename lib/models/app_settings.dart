import '../util/dates.dart';
import 'protocol.dart';

class AppSettings {
  const AppSettings({
    this.startDate,
    this.domperidoneTablets,
    this.tabletCountDate,
    this.remindersEnabled = false,
    this.reminderKinds = const {...EventKind.values},
    this.times = const ReminderTimes(),
  });

  /// Day 1 of the protocol.
  final DateTime? startDate;

  /// Domperidone tablets on hand when last counted.
  final int? domperidoneTablets;

  /// Day the tablets were counted (before that day's first dose). Falls back
  /// to the start date.
  final DateTime? tabletCountDate;

  final bool remindersEnabled;
  final Set<EventKind> reminderKinds;
  final ReminderTimes times;

  DateTime? get effectiveTabletCountDate => tabletCountDate ?? startDate;

  static const _unset = Object();

  AppSettings copyWith({
    Object? startDate = _unset,
    Object? domperidoneTablets = _unset,
    Object? tabletCountDate = _unset,
    bool? remindersEnabled,
    Set<EventKind>? reminderKinds,
    ReminderTimes? times,
  }) =>
      AppSettings(
        startDate: identical(startDate, _unset) ? this.startDate : startDate as DateTime?,
        domperidoneTablets:
            identical(domperidoneTablets, _unset) ? this.domperidoneTablets : domperidoneTablets as int?,
        tabletCountDate: identical(tabletCountDate, _unset) ? this.tabletCountDate : tabletCountDate as DateTime?,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderKinds: reminderKinds ?? this.reminderKinds,
        times: times ?? this.times,
      );

  /// Changes to anything in here require reminders to be rescheduled.
  Object get reminderSignature => Object.hash(
        startDate,
        remindersEnabled,
        Object.hashAllUnordered(reminderKinds),
        times,
      );

  Map<String, dynamic> toJson() => {
        if (startDate != null) 'startDate': dateKey(startDate!),
        if (domperidoneTablets != null) 'domperidoneTablets': domperidoneTablets,
        if (tabletCountDate != null) 'tabletCountDate': dateKey(tabletCountDate!),
        'remindersEnabled': remindersEnabled,
        'reminderKinds': [for (final k in reminderKinds) k.name],
        'times': times.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final kinds = json['reminderKinds'] as List<dynamic>?;
    return AppSettings(
      startDate: json['startDate'] is String ? parseDateKey(json['startDate'] as String) : null,
      domperidoneTablets: (json['domperidoneTablets'] as num?)?.toInt(),
      tabletCountDate: json['tabletCountDate'] is String ? parseDateKey(json['tabletCountDate'] as String) : null,
      remindersEnabled: json['remindersEnabled'] as bool? ?? false,
      reminderKinds: kinds == null
          ? {...EventKind.values}
          : {
              for (final name in kinds)
                for (final k in EventKind.values)
                  if (k.name == name) k,
            },
      times: json['times'] is Map<String, dynamic>
          ? ReminderTimes.fromJson(json['times'] as Map<String, dynamic>)
          : const ReminderTimes(),
    );
  }
}
