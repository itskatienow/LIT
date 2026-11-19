import 'dart:convert';

import '../models/app_settings.dart';
import '../models/day_entry.dart';
import '../util/dates.dart';

/// Contents of a backup file.
class BackupData {
  const BackupData({required this.settings, required this.entries, this.exportedAt});

  final AppSettings settings;
  final Map<String, DayEntry> entries;
  final DateTime? exportedAt;
}

/// The JSON backup format: everything needed to restore LIT on a new phone.
class Backup {
  Backup._();

  static const _format = 'lit-backup';
  static const _version = 1;

  static String fileName(DateTime now) => 'LIT-backup-${dateKey(now)}.json';

  static String encode({
    required AppSettings settings,
    required Map<String, DayEntry> entries,
    required DateTime now,
  }) {
    final keys = entries.keys.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'exportedAt': now.toIso8601String(),
      'settings': settings.toJson(),
      'entries': {for (final k in keys) k: entries[k]!.toJson()},
    });
  }

  /// Throws [FormatException] with a user-readable message if [text] isn't a
  /// LIT backup this version can read.
  static BackupData decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('That file isn’t a LIT backup (it isn’t valid JSON).');
    }
    if (json is! Map<String, dynamic> || json['format'] != _format) {
      throw const FormatException('That file isn’t a LIT backup.');
    }
    final version = json['version'];
    if (version is! int || version > _version) {
      throw const FormatException('This backup was made by a newer version of LIT.');
    }
    try {
      final entries = <String, DayEntry>{};
      final rawEntries = json['entries'] as Map<String, dynamic>? ?? const {};
      for (final e in rawEntries.entries) {
        parseDateKey(e.key); // validates the key
        entries[e.key] = DayEntry.fromJson(e.value as Map<String, dynamic>);
      }
      return BackupData(
        settings: AppSettings.fromJson(json['settings'] as Map<String, dynamic>? ?? const {}),
        entries: entries,
        exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? ''),
      );
    } catch (_) {
      throw const FormatException('This backup is damaged and can’t be restored.');
    }
  }
}
