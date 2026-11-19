import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_store.dart';
import '../data/trend_stats.dart';
import '../models/protocol.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/dates.dart';

final _ml = NumberFormat('#,##0.#');
final _int = NumberFormat('#,##0');

class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key, required this.store, required this.onOpenDate});

  final AppStore store;
  final ValueChanged<DateTime> onOpenDate;

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  int _rangeDays = 14;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final store = widget.store;
          final now = today();
          final stats = store.stats(asOf: now);
          final recent = store.recentEntries();
          return PageBody(
            children: [
              if (recent.isEmpty) ...[
                const _EmptyBanner(),
                const SizedBox(height: 4),
              ],
              _StatGrid(stats: stats),
              SectionHeader(
                'Daily output',
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7D')),
                    ButtonSegment(value: 14, label: Text('14D')),
                    ButtonSegment(value: 30, label: Text('30D')),
                  ],
                  selected: {_rangeDays},
                  onSelectionChanged: (s) => setState(() => _rangeDays = s.first),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                  child: OutputBarChart(
                    days: [
                      for (var i = _rangeDays - 1; i >= 0; i--)
                        (
                          date: addDays(now, -i),
                          ml: store.entryFor(addDays(now, -i)).countedOutputMl,
                        ),
                    ],
                  ),
                ),
              ),
              if (stats.adherence.isNotEmpty) ...[
                const SectionHeader('Logged vs. scheduled · Day 1 to today'),
                _AdherenceCard(items: stats.adherence),
              ],
              if (recent.isNotEmpty) ...[
                const SectionHeader('Recent days'),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        _RecentTile(
                          date: recent[i].date,
                          day: store.dayNumber(recent[i].date),
                          ml: recent[i].entry.countedOutputMl,
                          sessions: recent[i].entry.countedSessions,
                          tablets: recent[i].entry.domperidoneTablets,
                          onTap: () => widget.onOpenDate(recent[i].date),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.insights_rounded, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nothing logged yet. Entries from the Dashboard will show up here.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final TrendStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;

    String supplyCaption() {
      if (s.tabletsRemaining == null) return 'Enter your tablet count in Settings';
      final logged = '${_int.format(s.tabletsLoggedSinceCount)} logged since count';
      if (s.tabletsRemaining! <= 0) return '$logged · time to refill';
      if (s.supplyBeyondHorizon) return '$logged · lasts over a year';
      final through = s.supplyLastsThrough;
      if (through == null) return logged;
      if (through.isBefore(today())) return '$logged · not enough for today';
      return '$logged · lasts through ${formatShort(through)}';
    }

    final tiles = [
      _StatTile(
        icon: Icons.local_drink_outlined,
        label: 'Total output',
        value: s.daysWithOutput == 0 ? '—' : '${_ml.format(s.totalOutputMl)} mL',
        caption: s.daysWithOutput == 0
            ? 'No output recorded yet'
            : 'across ${s.daysWithOutput} ${s.daysWithOutput == 1 ? 'day' : 'days'}',
      ),
      _StatTile(
        icon: Icons.show_chart_rounded,
        label: 'Latest 7-day average',
        value: s.recentAverageMl == null ? '—' : '${_ml.format(s.recentAverageMl)} mL/day',
        caption: s.recentWindowEnd == null
            ? 'Needs recorded output'
            : '${formatMonthDay(s.recentWindowStart!)}–${formatMonthDay(s.recentWindowEnd!)} · '
                '${s.recentDaysLogged} ${s.recentDaysLogged == 1 ? 'day' : 'days'} logged',
      ),
      _StatTile(
        icon: Icons.emoji_events_outlined,
        label: 'Highest daily output',
        value: s.highestDailyMl == null ? '—' : '${_ml.format(s.highestDailyMl)} mL',
        caption: s.highestDailyDate == null ? 'Needs recorded output' : formatShort(s.highestDailyDate!),
      ),
      _StatTile(
        icon: eventIcon(EventKind.pump),
        label: 'Pump sessions',
        value: _int.format(s.totalPumpSessions),
        caption: s.powerPumpDays == 0
            ? 'total recorded'
            : 'total · ${s.powerPumpDays} power-pump ${s.powerPumpDays == 1 ? 'day' : 'days'}',
      ),
      _StatTile(
        icon: eventIcon(EventKind.domperidone),
        label: 'Domperidone remaining (est.)',
        value: s.tabletsRemaining == null ? '—' : '${_int.format(s.tabletsRemaining)} tablets',
        caption: supplyCaption(),
        wide: true,
        warn: s.tabletsRemaining != null &&
            (s.tabletsRemaining! <= 0 ||
                (s.supplyLastsThrough != null && daysBetween(today(), s.supplyLastsThrough!) < 7)),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(width: t.wide && columns == 2 ? constraints.maxWidth : cell, child: t),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.wide = false,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final bool wide;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = warn ? scheme.error : scheme.primary;
    return Card(
      color: warn ? scheme.errorContainer.withValues(alpha: 0.5) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 128),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(height: 10),
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 2),
              Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple bar chart of daily output; days without a value show a stub.
class OutputBarChart extends StatelessWidget {
  const OutputBarChart({super.key, required this.days});

  final List<({DateTime date, double? ml})> days;

  static double _niceCeil(double v) {
    if (v <= 0) return 100;
    final magnitude = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (m * magnitude >= v) return m * magnitude;
    }
    return 10 * magnitude;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxMl = days.fold<double>(0, (m, d) => math.max(m, d.ml ?? 0));
    final top = _niceCeil(maxMl);
    final showValues = days.length <= 7;
    final labelEvery = days.length <= 7 ? 1 : (days.length <= 14 ? 2 : 5);
    final barGap = days.length <= 14 ? 4.0 : 1.5;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    const valueSpace = 18.0;
    const axisWidth = 40.0;

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: LayoutBuilder(
            builder: (context, c) {
              final plotHeight = c.maxHeight - valueSpace;
              double yFor(double fraction) => valueSpace + plotHeight * (1 - fraction);
              return Stack(
                clipBehavior: Clip.none, // the "0" axis label straddles the bottom edge
                children: [
                  for (final f in [0.0, 0.5, 1.0]) ...[
                    Positioned(
                      left: axisWidth,
                      right: 0,
                      top: yFor(f),
                      child: Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    Positioned(
                      left: 0,
                      width: axisWidth - 6,
                      top: yFor(f) - 7,
                      child: Text(_int.format(top * f), textAlign: TextAlign.right, style: axisStyle),
                    ),
                  ],
                  Positioned.fill(
                    left: axisWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in days)
                          Expanded(
                            child: Tooltip(
                              message: '${formatShort(d.date)}: ${d.ml == null ? 'not recorded' : '${_ml.format(d.ml)} mL'}',
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: barGap / 2),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (showValues && d.ml != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(_ml.format(d.ml), style: axisStyle),
                                        ),
                                      ),
                                    Container(
                                      height: d.ml == null ? 2 : math.max(3, plotHeight * d.ml! / top),
                                      decoration: BoxDecoration(
                                        color: d.ml == null
                                            ? scheme.outlineVariant
                                            : (isSameDay(d.date, today())
                                                ? scheme.primary
                                                : scheme.primary.withValues(alpha: 0.7)),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: axisWidth),
          child: Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Text(
                    (days.length - 1 - i) % labelEvery == 0
                        ? (days.length <= 7
                            ? DateFormat('E').format(days[i].date).substring(0, 2)
                            : '${days[i].date.day}')
                        : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: axisStyle,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: axisWidth),
            child: Text(
              'mL per day · ${formatMonthDay(days.first.date)} – ${formatMonthDay(days.last.date)}',
              style: axisStyle,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdherenceCard extends StatelessWidget {
  const _AdherenceCard({required this.items});

  final List<Adherence> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text(items[i].label, style: theme.textTheme.titleSmall)),
                  Text(
                    items[i].scheduled == 0
                        ? '${items[i].logged} ${items[i].unit}'
                        : '${items[i].logged} / ${items[i].scheduled} ${items[i].unit}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: items[i].scheduled == 0 ? 0 : items[i].ratio,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.date,
    required this.day,
    required this.ml,
    required this.sessions,
    required this.tablets,
    required this.onTap,
  });

  final DateTime date;
  final int? day;
  final double? ml;
  final int sessions;
  final int tablets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = Protocol.phaseForDay(day);
    final pScheme = phaseScheme(phase, theme.brightness);
    final parts = [
      if (day != null && day! >= 1) 'Day $day · ${phase.label}',
      if (sessions > 0) '$sessions ${sessions == 1 ? 'session' : 'sessions'}',
      if (tablets > 0) '$tablets ${tablets == 1 ? 'tablet' : 'tablets'}',
    ];
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: pScheme.primaryContainer,
        foregroundColor: pScheme.onPrimaryContainer,
        child: Icon(phaseIcon(phase), size: 20),
      ),
      title: Text(formatShort(date)),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      trailing: Text(
        ml == null ? '—' : '${_ml.format(ml)} mL',
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
