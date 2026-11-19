import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lit/data/app_store.dart';
import 'package:lit/data/backup.dart';
import 'package:lit/models/app_settings.dart';
import 'package:lit/models/day_entry.dart';
import 'package:lit/models/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final settings = AppSettings(
    startDate: DateTime(2026, 11, 1),
    domperidoneTablets: 400,
    tabletCountDate: DateTime(2026, 11, 3),
    remindersEnabled: true,
    reminderKinds: const {EventKind.domperidone, EventKind.pump},
    times: const ReminderTimes(progesterone: 21 * 60 + 30),
  );
  final entries = {
    '2026-11-02': const DayEntry(domperidoneTablets: 3, progesteroneTaken: true, notes: 'Day two ✓'),
    '2026-12-15': const DayEntry(pumped: true, pumpSessions: 7, powerPumped: true, outputMl: 42.5),
  };

  test('round-trips settings and entries', () {
    final text = Backup.encode(settings: settings, entries: entries, now: DateTime(2026, 12, 20, 9, 30));
    final restored = Backup.decode(text);

    expect(restored.exportedAt, DateTime(2026, 12, 20, 9, 30));
    expect(restored.settings.startDate, settings.startDate);
    expect(restored.settings.domperidoneTablets, 400);
    expect(restored.settings.tabletCountDate, DateTime(2026, 11, 3));
    expect(restored.settings.remindersEnabled, isTrue);
    expect(restored.settings.reminderKinds, {EventKind.domperidone, EventKind.pump});
    expect(restored.settings.times, settings.times);
    expect(restored.entries.keys, entries.keys);
    expect(restored.entries['2026-11-02']!.notes, 'Day two ✓');
    expect(restored.entries['2026-12-15']!.outputMl, 42.5);
    expect(restored.entries['2026-12-15']!.powerPumped, isTrue);
  });

  test('names the file by date', () {
    expect(Backup.fileName(DateTime(2026, 1, 5, 14)), 'LIT-backup-2026-01-05.json');
  });

  test('rejects files that are not LIT backups', () {
    expect(() => Backup.decode('not json'), throwsFormatException);
    expect(() => Backup.decode('{"hello": "world"}'), throwsFormatException);
    expect(() => Backup.decode(jsonEncode({'format': 'lit-backup', 'version': 99})), throwsFormatException);
    expect(
      () => Backup.decode(jsonEncode({
        'format': 'lit-backup',
        'version': 1,
        'entries': {'not-a-date': {}},
      })),
      throwsFormatException,
    );
  });

  test('restoring replaces store data and persists it', () async {
    SharedPreferences.setMockInitialValues({
      'lit.entries.v1': jsonEncode({'2026-10-01': const DayEntry(domperidoneTablets: 1).toJson()}),
    });
    final store = await AppStore.load();
    final versionBefore = store.dataVersion;

    final backup = Backup.decode(Backup.encode(settings: settings, entries: entries, now: DateTime(2026, 12, 20)));
    await store.replaceAll(settings: backup.settings, entries: backup.entries);

    expect(store.entries.keys, unorderedEquals(entries.keys));
    expect(store.settings.domperidoneTablets, 400);
    expect(store.dataVersion, greaterThan(versionBefore));

    final reloaded = await AppStore.load();
    expect(reloaded.entries.keys, unorderedEquals(entries.keys));
    expect(reloaded.settings.startDate, DateTime(2026, 11, 1));
  });

  test('remembers the last export', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    expect(store.lastExportAt, isNull);
    await store.markExported(DateTime(2026, 12, 20, 8));
    expect((await AppStore.load()).lastExportAt, DateTime(2026, 12, 20, 8));
  });
}
