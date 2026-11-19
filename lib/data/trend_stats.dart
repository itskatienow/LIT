import 'dart:math' as math;

import '../models/app_settings.dart';
import '../models/day_entry.dart';
import '../models/protocol.dart';
import '../util/dates.dart';

class Adherence {
  const Adherence(this.label, this.logged, this.scheduled, this.unit);

  final String label;
  final int logged;
  final int scheduled;
  final String unit;

  double get ratio => scheduled == 0 ? 0 : math.min(1, logged / scheduled);
}

/// Summary numbers for the Trends page.
class TrendStats {
  const TrendStats({
    required this.totalOutputMl,
    required this.daysWithOutput,
    required this.recentAverageMl,
    required this.recentDaysLogged,
    required this.recentWindowStart,
    required this.recentWindowEnd,
    required this.highestDailyMl,
    required this.highestDailyDate,
    required this.totalPumpSessions,
    required this.powerPumpDays,
    required this.tabletsRemaining,
    required this.tabletsLoggedSinceCount,
    required this.supplyLastsThrough,
    required this.supplyBeyondHorizon,
    required this.adherence,
  });

  final double totalOutputMl;
  final int daysWithOutput;

  /// Average of the days with recorded output inside the latest 7-day window
  /// (the 7 calendar days ending on the most recent day with output).
  final double? recentAverageMl;
  final int recentDaysLogged;
  final DateTime? recentWindowStart;
  final DateTime? recentWindowEnd;

  final double? highestDailyMl;
  final DateTime? highestDailyDate;

  final int totalPumpSessions;
  final int powerPumpDays;

  /// Tablets on hand minus tablets logged since the count. Null until a
  /// count is entered in Settings.
  final int? tabletsRemaining;
  final int tabletsLoggedSinceCount;

  /// Last day the remaining tablets cover on the scheduled ramp-up.
  final DateTime? supplyLastsThrough;
  final bool supplyBeyondHorizon;

  final List<Adherence> adherence;

  static const _supplyHorizonDays = 365;

  static TrendStats compute({
    required AppSettings settings,
    required Map<String, DayEntry> entries,
    required DateTime today,
  }) {
    final dated = [
      for (final e in entries.entries) (date: parseDateKey(e.key), entry: e.value),
    ]..sort((a, b) => a.date.compareTo(b.date));

    // ---- Output ----
    var total = 0.0;
    var daysWithOutput = 0;
    double? highest;
    DateTime? highestDate;
    DateTime? latestOutputDate;
    var sessions = 0;
    var powerDays = 0;

    for (final d in dated) {
      sessions += d.entry.countedSessions;
      if (d.entry.countedPowerPump) powerDays++;
      final ml = d.entry.countedOutputMl;
      if (ml == null) continue;
      total += ml;
      daysWithOutput++;
      latestOutputDate = d.date;
      if (highest == null || ml > highest) {
        highest = ml;
        highestDate = d.date;
      }
    }

    double? recentAvg;
    var recentDays = 0;
    DateTime? windowStart;
    if (latestOutputDate != null) {
      windowStart = addDays(latestOutputDate, -6);
      var sum = 0.0;
      for (final d in dated) {
        final ml = d.entry.countedOutputMl;
        if (ml == null || d.date.isBefore(windowStart) || d.date.isAfter(latestOutputDate)) continue;
        sum += ml;
        recentDays++;
      }
      recentAvg = recentDays == 0 ? null : sum / recentDays;
    }

    // ---- Domperidone inventory ----
    int? remaining;
    var loggedSinceCount = 0;
    DateTime? lastsThrough;
    var beyondHorizon = false;
    final countDate = settings.effectiveTabletCountDate;
    if (settings.domperidoneTablets != null) {
      for (final d in dated) {
        if (countDate == null || !d.date.isBefore(countDate)) {
          loggedSinceCount += d.entry.domperidoneTablets;
        }
      }
      remaining = settings.domperidoneTablets! - loggedSinceCount;

      final start = settings.startDate;
      if (start != null) {
        var left = remaining;
        beyondHorizon = true;
        for (var i = 0; i <= _supplyHorizonDays; i++) {
          final date = addDays(today, i);
          final day = Protocol.dayNumber(start, date)!;
          var need = day < 1 ? 0 : Protocol.domperidoneTabletsForDay(day);
          if (i == 0) {
            // Today's logged tablets are already subtracted above.
            need = math.max(0, need - (entries[dateKey(date)]?.domperidoneTablets ?? 0));
          }
          if (need > left) {
            lastsThrough = addDays(date, -1);
            beyondHorizon = false;
            break;
          }
          left -= need;
        }
      }
    }

    // ---- Adherence (Day 1 through today) ----
    final adherence = <Adherence>[];
    final start = settings.startDate;
    final todayNum = Protocol.dayNumber(start, today);
    if (start != null && todayNum != null && todayNum >= 1) {
      var progScheduled = 0, progLogged = 0;
      var estScheduled = 0, estLogged = 0;
      var domScheduled = 0, domLogged = 0;
      var pumpScheduled = 0, pumpLogged = 0;
      for (var day = 1; day <= todayNum; day++) {
        final date = Protocol.dateForDay(start, day);
        final entry = entries[dateKey(date)] ?? DayEntry.empty;
        if (Protocol.progesteroneScheduled(day)) progScheduled++;
        if (entry.progesteroneTaken) progLogged++;
        if (Protocol.estradiolSlot(day, date) != null) estScheduled++;
        if (entry.estradiolTaken) estLogged++;
        domScheduled += Protocol.domperidoneTabletsForDay(day);
        domLogged += entry.domperidoneTablets;
        if (Protocol.pumpingScheduled(day)) pumpScheduled += Protocol.pumpSessionsPerDay;
        pumpLogged += entry.countedSessions;
      }
      adherence
        ..add(Adherence('Domperidone', domLogged, domScheduled, 'tablets'))
        ..add(Adherence('Estradiol', estLogged, estScheduled, 'injections'))
        ..add(Adherence('Progesterone', progLogged, progScheduled, 'nights'));
      if (pumpScheduled > 0 || pumpLogged > 0) {
        adherence.add(Adherence('Pumping', pumpLogged, pumpScheduled, 'sessions'));
      }
    }

    return TrendStats(
      totalOutputMl: total,
      daysWithOutput: daysWithOutput,
      recentAverageMl: recentAvg,
      recentDaysLogged: recentDays,
      recentWindowStart: windowStart,
      recentWindowEnd: latestOutputDate,
      highestDailyMl: highest,
      highestDailyDate: highestDate,
      totalPumpSessions: sessions,
      powerPumpDays: powerDays,
      tabletsRemaining: remaining,
      tabletsLoggedSinceCount: loggedSinceCount,
      supplyLastsThrough: lastsThrough,
      supplyBeyondHorizon: beyondHorizon,
      adherence: adherence,
    );
  }
}
