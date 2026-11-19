import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../data/app_store.dart';
import '../data/backup.dart';
import '../models/protocol.dart';
import '../services/notification_service.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/dates.dart';
import '../util/numbers.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.notifications,
  });

  final AppStore store;
  final NotificationService notifications;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _tablets;
  final _weeklyDose = TextEditingController();
  final _strength = TextEditingController();
  final _dailyDose = TextEditingController();
  final _progesterone = TextEditingController();

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _tablets = TextEditingController(
      text: _store.settings.domperidoneTablets?.toString() ?? '',
    );
    _loadDoseFields();
  }

  @override
  void dispose() {
    _tablets.dispose();
    _weeklyDose.dispose();
    _strength.dispose();
    _dailyDose.dispose();
    _progesterone.dispose();
    super.dispose();
  }

  void _loadDoseFields() {
    final settings = _store.settings;
    final plan = settings.estradiol;
    String text(double? v) => v == null ? '' : formatDecimal(v);
    _weeklyDose.text = text(plan.weeklyDoseMg);
    _strength.text = text(plan.strengthMgPerMl);
    _dailyDose.text = text(plan.dailyDoseMg);
    _progesterone.text = text(settings.progesteroneMg);
  }

  /// Up to 4 digits and 2 decimals, e.g. "12.5".
  static final _decimalInput = TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        RegExp(r'^\d{0,4}(\.\d{0,2})?$').hasMatch(newValue.text)
        ? newValue
        : oldValue,
  );

  /// A positive amount, or null for blank or zero.
  static double? _parseAmount(String text) {
    final v = double.tryParse(text);
    return v != null && v > 0 ? v : null;
  }

  Future<void> _updateEstradiol(
    EstradiolPlan Function(EstradiolPlan current) change,
  ) => _store.updateSettings(
    _store.settings.copyWith(estradiol: change(_store.settings.estradiol)),
  );

  Future<DateTime?> _pickDate(DateTime? initial, String help) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: help,
    );
    return picked == null ? null : dateOnly(picked);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDate(
      _store.settings.startDate,
      'Start date (Day 1)',
    );
    if (picked != null)
      await _store.updateSettings(_store.settings.copyWith(startDate: picked));
  }

  Future<void> _pickCountDate() async {
    final picked = await _pickDate(
      _store.settings.effectiveTabletCountDate,
      'Tablets counted on',
    );
    if (picked != null)
      await _store.updateSettings(
        _store.settings.copyWith(tabletCountDate: picked),
      );
  }

  Future<void> _pickTime(
    int current,
    ReminderTimes Function(int minutes) apply,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked != null) {
      await _store.updateSettings(
        _store.settings.copyWith(
          times: apply(picked.hour * 60 + picked.minute),
        ),
      );
    }
  }

  Future<void> _setRemindersEnabled(bool enabled) async {
    if (enabled) {
      final granted = await widget.notifications.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications are blocked for LIT. Allow them in system settings.',
              ),
            ),
          );
        }
        return;
      }
    }
    await _store.updateSettings(
      _store.settings.copyWith(remindersEnabled: enabled),
    );
  }

  Future<void> _toggleKind(EventKind kind, bool on) async {
    final kinds = {..._store.settings.reminderKinds};
    on ? kinds.add(kind) : kinds.remove(kind);
    await _store.updateSettings(_store.settings.copyWith(reminderKinds: kinds));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scheduleTest() async {
    final at = await widget.notifications.scheduleTest();
    if (at == null) return;
    _toast(
      'Test reminder set for ${formatMinuteOfDay(at.hour * 60 + at.minute)}. Lock your phone and wait.',
    );
  }

  Future<void> _export() async {
    final now = DateTime.now();
    final text = Backup.encode(
      settings: _store.settings,
      entries: _store.entries,
      now: now,
    );
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save LIT backup',
        fileName: Backup.fileName(now),
        bytes: utf8.encode(text),
        mimeType: 'application/json',
      );
      if (uri == null) return; // cancelled
      await _store.markExported(now);
      _toast('Backup saved');
    } catch (e) {
      _toast('Couldn’t save the backup: $e');
    }
  }

  Future<void> _restore() async {
    final BackupData backup;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a LIT backup',
      );
      if (file == null) return; // cancelled
      backup = Backup.decode(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
      );
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    } catch (e) {
      _toast('Couldn’t open that file: $e');
      return;
    }
    if (!mounted) return;

    final current = _store.entries.length;
    final incoming = backup.entries.length;
    final from = backup.exportedAt == null
        ? ''
        : ' from ${formatLong(backup.exportedAt!)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.settings_backup_restore_rounded),
        title: const Text('Restore this backup?'),
        content: Text(
          'Backup$from with $incoming logged ${incoming == 1 ? 'day' : 'days'}.\n\n'
          'It replaces everything currently in LIT: your settings and '
          '$current logged ${current == 1 ? 'day' : 'days'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    var settings = backup.settings;
    // Reminders need this phone's permission, which a backup can't carry over.
    if (settings.remindersEnabled && widget.notifications.isSupported) {
      final granted = await widget.notifications.requestPermission();
      if (!granted) settings = settings.copyWith(remindersEnabled: false);
    }
    await _store.replaceAll(settings: settings, entries: backup.entries);
    _tablets.text = settings.domperidoneTablets?.toString() ?? '';
    _loadDoseFields();
    _toast('Restored $incoming logged ${incoming == 1 ? 'day' : 'days'}');
  }

  Future<void> _confirmClear() async {
    final count = _store.entries.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: const Text('Clear all logged days?'),
        content: Text(
          'This permanently deletes $count logged ${count == 1 ? 'day' : 'days'} on this device. '
          'Your settings are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _store.clearEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_store, widget.notifications.status]),
        builder: (context, _) {
          final theme = Theme.of(context);
          final settings = _store.settings;
          final start = settings.startDate;
          final times = settings.times;
          final estradiol = settings.estradiol;
          final estradiolMorningUse = estradiol.timeUsage(
            EstradiolSlot.morning,
          );
          final estradiolEveningUse = estradiol.timeUsage(
            EstradiolSlot.evening,
          );
          final status = widget.notifications.status.value;

          return PageBody(
            children: [
              const SectionHeader('Protocol'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Start date'),
                  subtitle: Text(
                    start == null
                        ? 'Not set · tap to choose Day 1'
                        : '${formatLong(start)} · Day 1',
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickStart,
                ),
              ),
              if (start != null) ...[
                const SectionHeader('Key dates'),
                _KeyDatesCard(start: start),
              ],
              const SectionHeader('Estradiol'),
              _estradiolCard(theme, estradiol),
              const SectionHeader('Progesterone'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: TextField(
                    key: const ValueKey('progesterone-dose'),
                    controller: _progesterone,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalInput],
                    decoration: InputDecoration(
                      labelText: 'Daily dose',
                      suffixText: 'mg',
                      prefixIcon: Icon(eventIcon(EventKind.progesterone)),
                    ),
                    onChanged: (text) => _store.updateSettings(
                      _store.settings.copyWith(
                        progesteroneMg: _parseAmount(text),
                      ),
                    ),
                  ),
                ),
              ),
              const SectionHeader('Domperidone inventory'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.event_note_outlined),
                      title: const Text('Counted on'),
                      subtitle: Text(
                        settings.tabletCountDate != null
                            ? formatLong(settings.tabletCountDate!)
                            : start != null
                            ? '${formatLong(start)} (start date)'
                            : 'Same as start date',
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: _pickCountDate,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: TextField(
                        controller: _tablets,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Tablets on hand',
                          suffixText:
                              '${Protocol.domperidoneTabletMg}mg tablets',
                          prefixIcon: Icon(Icons.medication_outlined),
                        ),
                        onChanged: (text) => _store.updateSettings(
                          _store.settings.copyWith(
                            domperidoneTablets: int.tryParse(text),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Schedule times'),
              Card(
                child: Column(
                  children: [
                    if (estradiolMorningUse != null)
                      _TimeTile(
                        icon: eventIcon(EventKind.estradiol),
                        title: 'Estradiol · morning',
                        subtitle: estradiolMorningUse,
                        minutes: times.estradiolMorning,
                        onTap: () => _pickTime(
                          times.estradiolMorning,
                          (m) => times.copyWith(estradiolMorning: m),
                        ),
                      ),
                    if (estradiolEveningUse != null)
                      _TimeTile(
                        icon: eventIcon(EventKind.estradiol),
                        title: 'Estradiol · evening',
                        subtitle: estradiolEveningUse,
                        minutes: times.estradiolEvening,
                        onTap: () => _pickTime(
                          times.estradiolEvening,
                          (m) => times.copyWith(estradiolEvening: m),
                        ),
                      ),
                    _TimeTile(
                      icon: eventIcon(EventKind.progesterone),
                      title: 'Progesterone · nightly',
                      subtitle: 'Days 1–${Protocol.lastProgesteroneDay}',
                      minutes: times.progesterone,
                      onTap: () => _pickTime(
                        times.progesterone,
                        (m) => times.copyWith(progesterone: m),
                      ),
                    ),
                    _TimeTile(
                      icon: eventIcon(EventKind.powerPump),
                      title: 'Power pumping · evening',
                      subtitle: 'From Day ${Protocol.powerPumpingStartDay}',
                      minutes: times.powerPump,
                      onTap: () => _pickTime(
                        times.powerPump,
                        (m) => times.copyWith(powerPump: m),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Text(
                        'Domperidone (6 AM, noon, 6 PM, midnight) and pumping times follow the protocol.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Reminders'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.notifications_active_outlined,
                      ),
                      title: const Text('Medication & pumping reminders'),
                      subtitle: switch (_reminderProblem(
                        status,
                        settings.remindersEnabled,
                        start != null,
                      )) {
                        final problem? => Text(
                          problem,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        null => null,
                      },
                      value: settings.remindersEnabled,
                      onChanged: status.supported ? _setRemindersEnabled : null,
                    ),
                    if (settings.remindersEnabled && status.supported) ...[
                      if (!status.exactAlarms &&
                          defaultTargetPlatform == TargetPlatform.android)
                        ListTile(
                          leading: const Icon(Icons.alarm_on_outlined),
                          title: const Text('Allow exact timing'),
                          subtitle: const Text(
                            'Without it, Android may deliver reminders several minutes late.',
                          ),
                          trailing: const Icon(Icons.open_in_new_rounded),
                          onTap: widget.notifications.requestExactAlarms,
                        ),
                      const Divider(indent: 16, endIndent: 16),
                      for (final kind in EventKind.values)
                        CheckboxListTile(
                          secondary: Icon(eventIcon(kind)),
                          title: Text(kind.label),
                          value: settings.reminderKinds.contains(kind),
                          onChanged: (v) => _toggleKind(kind, v ?? false),
                        ),
                      const Divider(indent: 16, endIndent: 16),
                      if (showDebugTools) ...[
                        ListTile(
                          leading: const Icon(Icons.send_outlined),
                          title: const Text('Send a test notification'),
                          subtitle: const Text('Shows one right now'),
                          onTap: widget.notifications.showTest,
                        ),
                        ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('Test a scheduled reminder'),
                          subtitle: const Text(
                            'Arrives in 1 minute, the same way real reminders do. '
                            'Lock your phone and wait for it.',
                          ),
                          onTap: _scheduleTest,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SectionHeader('Backup & data'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.save_alt_rounded),
                      title: const Text('Export backup'),
                      subtitle: Text(
                        _store.lastExportAt == null
                            ? 'Save your settings and all logged days to a file'
                            : 'Last exported ${relativeDays(daysBetween(today(), _store.lastExportAt!))}',
                      ),
                      onTap: _export,
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.settings_backup_restore_rounded,
                      ),
                      title: const Text('Restore from backup'),
                      subtitle: const Text(
                        'Replaces current settings and logged days',
                      ),
                      onTap: _restore,
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Clear all logged days',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: Text(
                        '${_store.entries.length} days logged · settings are kept',
                      ),
                      enabled: _store.entries.isNotEmpty,
                      onTap: _confirmClear,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Text(
                  'LIT · Lactation Induction Tracker\n'
                  'Your data stays on this device. Follow your prescriber’s guidance on doses and timing.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _estradiolCard(ThemeData theme, EstradiolPlan plan) {
    const amountKeyboard = TextInputType.numberWithOptions(decimal: true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<EstradiolMethod>(
              showSelectedIcon: false,
              segments: [
                for (final m in EstradiolMethod.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {plan.method},
              onSelectionChanged: (s) =>
                  _updateEstradiol((p) => p.copyWith(method: s.first)),
            ),
            const SizedBox(height: 16),
            if (plan.method == EstradiolMethod.injection) ...[
              TextField(
                key: const ValueKey('estradiol-strength'),
                controller: _strength,
                keyboardType: amountKeyboard,
                inputFormatters: [_decimalInput],
                decoration: const InputDecoration(
                  labelText: 'Strength',
                  suffixText: 'mg/mL',
                  helperText: 'From the vial label, e.g. 5 mg/mL',
                  prefixIcon: Icon(Icons.science_outlined),
                ),
                onChanged: (text) => _updateEstradiol(
                  (p) => p.copyWith(strengthMgPerMl: _parseAmount(text)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('estradiol-weekly'),
                controller: _weeklyDose,
                keyboardType: amountKeyboard,
                inputFormatters: [_decimalInput],
                decoration: const InputDecoration(
                  labelText: 'Weekly dose',
                  suffixText: 'mg',
                  prefixIcon: Icon(Icons.date_range_outlined),
                ),
                onChanged: (text) => _updateEstradiol(
                  (p) => p.copyWith(weeklyDoseMg: _parseAmount(text)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Injections a week',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      for (final n in EstradiolPlan.injectionCounts)
                        ButtonSegment(value: n, label: Text('$n')),
                    ],
                    selected: {plan.injectionsPerWeek},
                    onSelectionChanged: (s) => _updateEstradiol(
                      (p) => p.copyWith(injectionsPerWeek: s.first),
                    ),
                  ),
                ],
              ),
            ] else
              TextField(
                key: const ValueKey('estradiol-daily'),
                controller: _dailyDose,
                keyboardType: amountKeyboard,
                inputFormatters: [_decimalInput],
                decoration: const InputDecoration(
                  labelText: 'Daily dose',
                  suffixText: 'mg',
                  prefixIcon: Icon(Icons.today_outlined),
                ),
                onChanged: (text) => _updateEstradiol(
                  (p) => p.copyWith(dailyDoseMg: _parseAmount(text)),
                ),
              ),
            const SizedBox(height: 16),
            _EstradiolSummary(plan: plan),
          ],
        ),
      ),
    );
  }

  /// Something the user needs to fix for reminders to work, or null.
  String? _reminderProblem(ReminderStatus status, bool enabled, bool hasStart) {
    if (!status.supported) return 'Available in the Android and iOS apps';
    if (!enabled) return null;
    if (status.error != null)
      return 'Couldn’t schedule reminders: ${status.error}';
    if (status.permissionGranted == false)
      return 'Notifications are blocked in system settings';
    if (!hasStart) return 'Set a start date to schedule reminders';
    return null;
  }
}

class _KeyDatesCard extends StatelessWidget {
  const _KeyDatesCard({required this.start});

  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = today();
    DateTime d(int day) => Protocol.dateForDay(start, day);
    final birth = Protocol.phaseStartDay(Phase.birth);
    final lactation = Protocol.phaseStartDay(Phase.lactation);

    return Card(
      child: Column(
        children: [
          for (final k in Protocol.keyDates)
            Builder(
              builder: (context) {
                final date = d(k.day);
                final rel = daysBetween(now, date);
                final past = rel < 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: past
                        ? scheme.primary
                        : scheme.primaryContainer,
                    foregroundColor: past
                        ? scheme.onPrimary
                        : scheme.onPrimaryContainer,
                    child: past
                        ? const Icon(Icons.check_rounded, size: 20)
                        : Text(
                            '${k.day}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                  title: Text(k.label),
                  subtitle: Text(
                    'Day ${k.day} · ${formatShort(date)} · ${relativeDays(rel)}',
                  ),
                );
              },
            ),
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              children: [
                _PhaseLine(
                  phase: Phase.build,
                  text:
                      'Days 1–${Protocol.buildDays} · ${formatMonthDay(start)} – ${formatMonthDay(d(Protocol.buildDays))}',
                ),
                _PhaseLine(
                  phase: Phase.birth,
                  text:
                      'Days $birth–${lactation - 1} · ${formatMonthDay(d(birth))} – ${formatMonthDay(d(lactation - 1))}',
                ),
                _PhaseLine(
                  phase: Phase.lactation,
                  text:
                      'Day $lactation onward · from ${formatMonthDay(d(lactation))}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseLine extends StatelessWidget {
  const _PhaseLine({required this.phase, required this.text});

  final Phase phase;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: phaseColor(phase),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              phase.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: onPhaseColor(phase),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// The calculated estradiol dose for the chosen method.
class _EstradiolSummary extends StatelessWidget {
  const _EstradiolSummary({required this.plan});

  final EstradiolPlan plan;

  String get _text {
    final dose = plan.doseLabel;
    return switch (plan.method) {
      EstradiolMethod.injection =>
        dose == null ? 'Enter your weekly dose' : '$dose per injection',
      EstradiolMethod.oral =>
        dose == null ? 'Enter your daily dose' : '$dose once a day',
      EstradiolMethod.sublingual =>
        dose == null
            ? 'Enter your daily dose'
            : '$dose morning + $dose evening',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _text,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.minutes,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        formatMinuteOfDay(minutes),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      onTap: onTap,
    );
  }
}
