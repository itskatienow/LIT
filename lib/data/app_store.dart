import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/day_entry.dart';
import '../models/protocol.dart';
import '../util/dates.dart';
import 'trend_stats.dart';

/// App state: settings plus one [DayEntry] per logged day, persisted locally
/// with shared_preferences.
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this._settings, this._entries, this._lastExportAt);

  static const _settingsKey = 'lit.settings.v1';
  static const _entriesKey = 'lit.entries.v1';
  static const _lastExportKey = 'lit.lastExport.v1';

  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();

    var settings = const AppSettings();
    final rawSettings = prefs.getString(_settingsKey);
    if (rawSettings != null) {
      try {
        settings = AppSettings.fromJson(jsonDecode(rawSettings) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('LIT: could not read settings: $e');
      }
    }

    final entries = <String, DayEntry>{};
    final rawEntries = prefs.getString(_entriesKey);
    if (rawEntries != null) {
      try {
        final map = jsonDecode(rawEntries) as Map<String, dynamic>;
        for (final e in map.entries) {
          entries[e.key] = DayEntry.fromJson(e.value as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('LIT: could not read entries: $e');
      }
    }

    final lastExport = DateTime.tryParse(prefs.getString(_lastExportKey) ?? '');

    return AppStore._(prefs, settings, entries, lastExport);
  }

  final SharedPreferences _prefs;
  AppSettings _settings;
  final Map<String, DayEntry> _entries;
  Timer? _saveTimer;

  /// Bumped when entries change outside the dashboard (e.g. cleared), so
  /// editors holding text controllers know to reload.
  int get dataVersion => _dataVersion;
  int _dataVersion = 0;

  AppSettings get settings => _settings;

  Map<String, DayEntry> get entries => Map.unmodifiable(_entries);

  /// When a backup was last exported from this device.
  DateTime? get lastExportAt => _lastExportAt;
  DateTime? _lastExportAt;

  DayEntry entryFor(DateTime date) => _entries[dateKey(date)] ?? DayEntry.empty;

  int? dayNumber(DateTime date) => Protocol.dayNumber(_settings.startDate, date);

  Phase phaseFor(DateTime date) => Protocol.phaseForDay(dayNumber(date));

  TrendStats stats({DateTime? asOf}) =>
      TrendStats.compute(settings: _settings, entries: _entries, today: asOf ?? today());

  /// Logged days, newest first.
  List<({DateTime date, DayEntry entry})> recentEntries({int limit = 14}) {
    final keys = _entries.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys.take(limit)) (date: parseDateKey(k), entry: _entries[k]!),
    ];
  }

  void saveEntry(DateTime date, DayEntry entry) {
    final key = dateKey(date);
    if (entry.isEmpty) {
      _entries.remove(key);
    } else {
      _entries[key] = entry;
    }
    notifyListeners();
    // Typing in a text field saves on every keystroke; batch the disk writes.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _writeEntries);
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  /// Replaces all settings and logged days, e.g. when restoring a backup.
  Future<void> replaceAll({required AppSettings settings, required Map<String, DayEntry> entries}) async {
    _saveTimer?.cancel();
    _settings = settings;
    _entries
      ..clear()
      ..addAll(entries);
    _dataVersion++;
    notifyListeners();
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    await _writeEntries();
  }

  Future<void> markExported(DateTime when) async {
    _lastExportAt = when;
    notifyListeners();
    await _prefs.setString(_lastExportKey, when.toIso8601String());
  }

  Future<void> clearEntries() async {
    _saveTimer?.cancel();
    _entries.clear();
    _dataVersion++;
    notifyListeners();
    await _prefs.remove(_entriesKey);
  }

  /// Writes any pending entry changes immediately (call when backgrounded).
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _writeEntries();
    }
  }

  Future<void> _writeEntries() => _prefs.setString(
        _entriesKey,
        jsonEncode({for (final e in _entries.entries) e.key: e.value.toJson()}),
      );

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
