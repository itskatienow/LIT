import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../models/app_settings.dart';
import '../models/day_entry.dart';
import '../models/protocol.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/dates.dart';
import '../util/numbers.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.store,
    required this.selectedDate,
    required this.onOpenSettings,
  });

  final AppStore store;
  final ValueNotifier<DateTime> selectedDate;
  final VoidCallback onOpenSettings;

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) selectedDate.value = dateOnly(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: selectedDate,
      builder: (context, date, _) {
        final isToday = isSameDay(date, today());
        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              if (!isToday)
                TextButton.icon(
                  onPressed: () => selectedDate.value = today(),
                  icon: const Icon(Icons.today_rounded),
                  label: const Text('Today'),
                ),
              IconButton(
                tooltip: 'Choose a date',
                onPressed: () => _pickDate(context, date),
                icon: const Icon(Icons.calendar_month_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListenableBuilder(
            listenable: store,
            builder: (context, _) => PageBody(
              children: [
                _DateNavigator(
                  date: date,
                  isToday: isToday,
                  onChanged: (d) => selectedDate.value = d,
                  onTap: () => _pickDate(context, date),
                ),
                const SizedBox(height: 8),
                PhaseHeader(
                  settings: store.settings,
                  date: date,
                  isToday: isToday,
                ),
                if (store.settings.startDate == null) ...[
                  const SizedBox(height: 12),
                  _SetupCard(onOpenSettings: onOpenSettings),
                ],
                DayEditor(
                  // New editor (fresh text fields) per date, or after data is cleared.
                  key: ValueKey('${dateKey(date)}#${store.dataVersion}'),
                  store: store,
                  date: date,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({
    required this.date,
    required this.isToday,
    required this.onChanged,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = formatWeekday(date);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: () => onChanged(addDays(date, -1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Text(
                    isToday ? 'Today · $weekday' : weekday,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isToday
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatMonthDayYear(date),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: () => onChanged(addDays(date, 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// The phase banner: Prime / Switch / Supply, day count and next milestone.
class PhaseHeader extends StatelessWidget {
  const PhaseHeader({
    super.key,
    required this.settings,
    required this.date,
    required this.isToday,
  });

  final AppSettings settings;
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = settings.startDate;
    final day = Protocol.dayNumber(start, date);
    final phase = Protocol.phaseForDay(day);
    final color = phaseColor(phase);
    final onColor = onPhaseColor(phase);

    String headline;
    String? suffix;
    String? caption;
    double? progress;

    if (start == null) {
      headline = 'Not started';
      caption = 'Set a start date to see your phase and schedule.';
    } else if (day! < 1) {
      headline = 'Not started';
      caption =
          'Day 1 is ${formatShort(start)} (${relativeDays(1 - day)}${isToday ? '' : ' from this date'}).';
    } else {
      switch (phase) {
        case Phase.build || Phase.birth:
          final dayInPhase = day - Protocol.phaseStartDay(phase) + 1;
          final length = Protocol.phaseLength(phase)!;
          headline = 'Day $dayInPhase';
          suffix = 'of $length';
          progress = dayInPhase / length;
          final left = length - dayInPhase;
          final next = (phase == Phase.build ? Phase.birth : Phase.lactation).label;
          caption = left == 0
              ? 'Last day before $next'
              : '$left ${left == 1 ? 'day' : 'days'} until $next';
        case Phase.lactation:
          headline = 'Day ${day - Protocol.phaseStartDay(Phase.lactation) + 1}';
        case Phase.notStarted:
          headline = 'Not started';
      }
    }

    final milestone = start != null && day != null
        ? _milestoneText(start, day)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(phaseIcon(phase), color: onColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phase == Phase.notStarted
                      ? 'PROTOCOL'
                      : '${phase.label.toUpperCase()} PHASE',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: onColor,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (day != null && day >= 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: onColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Protocol day $day',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                headline,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: onColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 8),
                Text(
                  suffix,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: onColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              color: onColor,
              backgroundColor: onColor.withValues(alpha: 0.18),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: 10),
            Text(
              caption,
              style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
            ),
          ],
          if (milestone != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.flag_outlined, size: 18, color: onColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    milestone,
                    style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String? _milestoneText(DateTime start, int day) {
    for (final k in Protocol.keyDates) {
      if (k.day == day) return 'Today: ${k.label}';
      if (k.day > day) {
        final when = Protocol.dateForDay(start, k.day);
        final rel = isToday ? ' · ${relativeDays(k.day - day)}' : '';
        return 'Next: ${k.label} — Day ${k.day}, ${formatShort(when)}$rel';
      }
    }
    return null;
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available_outlined),
        title: const Text('Set your start date'),
        subtitle: const Text(
          'Phases, schedules and reminders are based on Day 1.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onOpenSettings,
      ),
    );
  }
}

/// Inputs for one day. Saves as you go.
class DayEditor extends StatefulWidget {
  const DayEditor({super.key, required this.store, required this.date});

  final AppStore store;
  final DateTime date;

  @override
  State<DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<DayEditor> {
  late final TextEditingController _output;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final entry = widget.store.entryFor(widget.date);
    _output = TextEditingController(
      text: entry.outputMl == null ? '' : _formatMl(entry.outputMl!),
    );
    _notes = TextEditingController(text: entry.notes);
  }

  @override
  void dispose() {
    _output.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _formatMl(double ml) =>
      ml == ml.roundToDouble() ? ml.toInt().toString() : ml.toString();

  void _update(DayEntry Function(DayEntry current) change) {
    widget.store.saveEntry(
      widget.date,
      change(widget.store.entryFor(widget.date)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final date = widget.date;
    final entry = store.entryFor(date);
    final settings = store.settings;
    final start = settings.startDate;
    final day = store.dayNumber(date);
    final active = day != null && day >= 1;

    // ---- Subtitles describing what's scheduled ----
    final estradiol = settings.estradiol;
    final sublingual = estradiol.method == EstradiolMethod.sublingual;
    final estradiolNote = _estradiolNote(
      estradiol,
      active ? Protocol.estradiolSlots(day, date, estradiol) : null,
    );

    final progesteroneMg = settings.progesteroneMg;
    final progesteroneDose = progesteroneMg == null ? null : '${formatDecimal(progesteroneMg)} mg';
    final String progesteroneNote;
    if (progesteroneDose == null && !(active && day > Protocol.lastProgesteroneDay)) {
      progesteroneNote = 'Set your dose in Settings';
    } else if (!active) {
      progesteroneNote =
          '$progesteroneDose nightly, Days 1–${Protocol.lastProgesteroneDay}';
    } else if (Protocol.progesteroneScheduled(day)) {
      final left = Protocol.lastProgesteroneDay - day;
      progesteroneNote =
          '$progesteroneDose tonight · ${left == 0 ? 'last dose' : '$left ${left == 1 ? 'night' : 'nights'} left after tonight'}';
    } else {
      progesteroneNote =
          'Finished — last dose was Day ${Protocol.lastProgesteroneDay}';
    }

    final scheduledTablets = active
        ? Protocol.domperidoneTabletsForDay(day)
        : 0;
    final domperidoneNote = active
        ? '$scheduledTablets tablets scheduled (${Protocol.domperidoneMgForDay(day)} mg)'
        : '${Protocol.domperidoneTabletMg} mg tablets';

    final pumpingNote = !active || !Protocol.pumpingScheduled(day)
        ? (start == null
              ? 'Begins Day ${Protocol.pumpingStartDay}'
              : 'Begins Day ${Protocol.pumpingStartDay} · ${formatShort(Protocol.dateForDay(start, Protocol.pumpingStartDay))}')
        : '${Protocol.pumpSessionsPerDay} sessions scheduled · 15–20 min each';

    final powerNote = active && Protocol.powerPumpingScheduled(day)
        ? 'Once in the evening · 60 min routine'
        : 'Begins Day ${Protocol.powerPumpingStartDay}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Medications'),
        Card(
          child: Column(
            children: [
              ControlRow(
                icon: eventIcon(EventKind.estradiol),
                title: switch (estradiol.method) {
                  EstradiolMethod.injection => 'Estradiol Injection',
                  EstradiolMethod.oral => 'Oral Estradiol',
                  EstradiolMethod.sublingual => 'Sublingual Estradiol',
                },
                subtitle: estradiolNote,
                onTap: sublingual
                    ? null
                    : () => _update(
                        (e) => e.copyWith(
                          estradiolDoses: e.estradiolDoses > 0 ? 0 : 1,
                        ),
                      ),
                trailing: sublingual
                    ? CountStepper(
                        label: 'estradiol doses',
                        value: entry.estradiolDoses,
                        max: 2,
                        onChanged: (v) =>
                            _update((e) => e.copyWith(estradiolDoses: v)),
                      )
                    : Switch(
                        value: entry.estradiolDoses > 0,
                        onChanged: (v) => _update(
                          (e) => e.copyWith(estradiolDoses: v ? 1 : 0),
                        ),
                      ),
              ),
              const Divider(indent: 56),
              ControlRow(
                icon: eventIcon(EventKind.progesterone),
                title: 'Progesterone',
                subtitle: progesteroneNote,
                onTap: () => _update(
                  (e) => e.copyWith(progesteroneTaken: !e.progesteroneTaken),
                ),
                trailing: Switch(
                  value: entry.progesteroneTaken,
                  onChanged: (v) =>
                      _update((e) => e.copyWith(progesteroneTaken: v)),
                ),
              ),
              const Divider(indent: 56),
              ControlRow(
                icon: eventIcon(EventKind.domperidone),
                title: 'Domperidone',
                subtitle: domperidoneNote,
                trailing: CountStepper(
                  label: 'domperidone tablets',
                  value: entry.domperidoneTablets,
                  onChanged: (v) =>
                      _update((e) => e.copyWith(domperidoneTablets: v)),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Pumping'),
        Card(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                ControlRow(
                  icon: eventIcon(EventKind.pump),
                  title: 'Pumped',
                  subtitle: pumpingNote,
                  onTap: () => _update((e) => e.copyWith(pumped: !e.pumped)),
                  trailing: Switch(
                    value: entry.pumped,
                    onChanged: (v) => _update((e) => e.copyWith(pumped: v)),
                  ),
                ),
                if (entry.pumped) ...[
                  const Divider(indent: 56),
                  ControlRow(
                    icon: Icons.repeat_rounded,
                    title: 'Sessions',
                    subtitle: active && Protocol.pumpingScheduled(day)
                        ? 'of ${Protocol.pumpSessionsPerDay} scheduled'
                        : 'Pump sessions today',
                    trailing: CountStepper(
                      label: 'pump sessions',
                      value: entry.pumpSessions,
                      max: 24,
                      onChanged: (v) =>
                          _update((e) => e.copyWith(pumpSessions: v)),
                    ),
                  ),
                  const Divider(indent: 56),
                  ControlRow(
                    icon: eventIcon(EventKind.powerPump),
                    title: 'Power pumped',
                    subtitle: powerNote,
                    onTap: () =>
                        _update((e) => e.copyWith(powerPumped: !e.powerPumped)),
                    trailing: Switch(
                      value: entry.powerPumped,
                      onChanged: (v) =>
                          _update((e) => e.copyWith(powerPumped: v)),
                    ),
                  ),
                  const Divider(indent: 56),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: TextField(
                      controller: _output,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (oldValue, newValue) =>
                              RegExp(
                                r'^\d{0,5}(\.\d{0,1})?$',
                              ).hasMatch(newValue.text)
                              ? newValue
                              : oldValue,
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Total output',
                        suffixText: 'mL',
                        prefixIcon: Icon(Icons.local_drink_outlined),
                      ),
                      onChanged: (text) {
                        final ml = double.tryParse(text);
                        _update(
                          (e) => ml == null
                              ? e.copyWith(clearOutput: true)
                              : e.copyWith(outputMl: ml),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SectionHeader('Notes'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'Symptoms, side effects, supply changes, anything worth remembering…',
              ),
              onChanged: (text) => _update((e) => e.copyWith(notes: text)),
            ),
          ),
        ),
        if (active) ...[
          SectionHeader('Schedule · Day $day'),
          _ScheduleCard(
            day: day,
            date: date,
            times: settings.times,
            estradiol: estradiol,
            progesteroneMg: settings.progesteroneMg,
          ),
        ],
      ],
    );
  }

  /// [today] is null when the date is outside the protocol.
  static String _estradiolNote(EstradiolPlan plan, List<EstradiolSlot>? today) {
    final dose = plan.doseLabel;
    switch (plan.method) {
      case EstradiolMethod.injection:
        if (dose == null) return 'Set your weekly dose in Settings';
        if (today == null) return '$dose · ${plan.injectionDaysLabel}';
        if (today.isEmpty) return 'No injection today';
        return '$dose · ${today.first.label}';
      case EstradiolMethod.oral:
        return dose == null ? 'Set your daily dose in Settings' : '$dose · once a day';
      case EstradiolMethod.sublingual:
        return dose == null ? 'Set your daily dose in Settings' : '$dose morning + $dose evening';
    }
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.day,
    required this.date,
    required this.times,
    required this.estradiol,
    required this.progesteroneMg,
  });

  final int day;
  final DateTime date;
  final ReminderTimes times;
  final EstradiolPlan estradiol;
  final double? progesteroneMg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = Protocol.eventsFor(
      day: day,
      date: date,
      times: times,
      estradiol: estradiol,
      progesteroneMg: progesteroneMg,
    );
    final now = DateTime.now();
    final nextIndex = isSameDay(date, now)
        ? events.indexWhere((e) => e.at(date).isAfter(now))
        : -1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < events.length; i++)
              _ScheduleRow(event: events[i], isNext: i == nextIndex),
            if (Protocol.powerPumpingScheduled(day))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  'Power pumping: ${Protocol.powerPumpRoutine.join(' → ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.event, required this.isNext});

  final ScheduledEvent event;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: isNext
          ? BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              event.time,
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isNext
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(
            eventIcon(event.kind),
            size: 20,
            color: isNext ? scheme.onSecondaryContainer : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: event.title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isNext ? scheme.onSecondaryContainer : null,
                ),
                children: [
                  TextSpan(
                    text: '  ${event.detail}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isNext
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isNext)
            Text(
              'Up next',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}
