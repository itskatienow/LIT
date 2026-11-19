/// The lactation-induction protocol: phases, key dates, and the daily
/// medication and pumping schedule.
///
/// Days are numbered from 1: the start date is Day 1. Every protocol number
/// lives in [Protocol] so the plan can be adjusted in one place.
library;

import '../util/dates.dart';
import '../util/numbers.dart';

/// Shown as Prime (build), Switch (birth) and Supply (lactation); see [PhaseInfo.label].
enum Phase { notStarted, build, birth, lactation }

extension PhaseInfo on Phase {
  String get label => switch (this) {
        Phase.notStarted => 'Not started',
        Phase.build => 'Prime',
        Phase.birth => 'Switch',
        Phase.lactation => 'Supply',
      };
}

/// Things that appear on the daily schedule and can trigger a reminder.
enum EventKind { domperidone, estradiol, progesterone, pump, powerPump }

extension EventKindInfo on EventKind {
  String get label => switch (this) {
        EventKind.domperidone => 'Domperidone',
        EventKind.estradiol => 'Estradiol',
        EventKind.progesterone => 'Progesterone',
        EventKind.pump => 'Pumping sessions',
        EventKind.powerPump => 'Power pumping',
      };
}

enum EstradiolSlot { morning, evening }

extension EstradiolSlotInfo on EstradiolSlot {
  String get label => switch (this) {
        EstradiolSlot.morning => 'morning',
        EstradiolSlot.evening => 'evening',
      };

  String get short => switch (this) {
        EstradiolSlot.morning => 'AM',
        EstradiolSlot.evening => 'PM',
      };
}

enum EstradiolMethod { injection, oral, sublingual }

extension EstradiolMethodInfo on EstradiolMethod {
  String get label => switch (this) {
        EstradiolMethod.injection => 'Injection',
        EstradiolMethod.oral => 'Oral',
        EstradiolMethod.sublingual => 'Sublingual',
      };
}

/// How estradiol is taken and how much, as set in Settings.
///
/// Injections: a weekly dose split over 1–3 injections on fixed days, each
/// rounded up to the next [injectionStepMg]. Oral: the daily dose once, in
/// the morning. Sublingual: half the daily dose morning and evening.
class EstradiolPlan {
  const EstradiolPlan({
    this.method = EstradiolMethod.injection,
    this.weeklyDoseMg = 6,
    this.injectionsPerWeek = 3,
    this.strengthMgPerMl,
    this.dailyDoseMg,
  });

  final EstradiolMethod method;

  /// Injections: total per week, in mg.
  final double? weeklyDoseMg;

  /// Injections: 1, 2 or 3 (see [injectionDays]).
  final int injectionsPerWeek;

  /// Injections: the vial's concentration, used to show the volume to draw.
  final double? strengthMgPerMl;

  /// Oral and sublingual: total per day, in mg.
  final double? dailyDoseMg;

  static const injectionCounts = [1, 2, 3];

  /// Each injection is rounded up to a multiple of this.
  static const injectionStepMg = 0.5;

  /// Which days (and when) each weekly injection count falls on.
  static const injectionDays = <int, Map<int, EstradiolSlot>>{
    1: {DateTime.wednesday: EstradiolSlot.morning},
    2: {DateTime.wednesday: EstradiolSlot.morning, DateTime.saturday: EstradiolSlot.evening},
    3: {
      DateTime.wednesday: EstradiolSlot.morning,
      DateTime.friday: EstradiolSlot.evening,
      DateTime.sunday: EstradiolSlot.morning,
    },
  };

  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  Map<int, EstradiolSlot> get _injectionDays => injectionDays[injectionsPerWeek] ?? injectionDays[3]!;

  /// The weekly dose split evenly, before rounding.
  double? get exactInjectionMg {
    final weekly = weeklyDoseMg;
    return weekly == null ? null : weekly / _injectionDays.length;
  }

  /// One injection: the weekly dose split evenly, rounded up to the next
  /// [injectionStepMg].
  double? get injectionDoseMg {
    final exact = exactInjectionMg;
    if (exact == null) return null;
    // The allowance stops float noise (2.0000000001) from adding a step.
    return (exact / injectionStepMg - 1e-9).ceil() * injectionStepMg;
  }

  bool get injectionRoundedUp {
    final exact = exactInjectionMg, dose = injectionDoseMg;
    return exact != null && dose != null && dose - exact > 1e-9;
  }

  /// What the rounded injections add up to in a week.
  double? get injectedPerWeekMg {
    final dose = injectionDoseMg;
    return dose == null ? null : dose * _injectionDays.length;
  }

  /// Volume to draw for one injection; null until the strength is set.
  double? get injectionVolumeMl {
    final dose = injectionDoseMg, strength = strengthMgPerMl;
    return dose == null || strength == null ? null : dose / strength;
  }

  /// One dose for the current method, in mg; null until the dose is set.
  double? get doseMg => switch (method) {
        EstradiolMethod.injection => injectionDoseMg,
        EstradiolMethod.oral => dailyDoseMg,
        EstradiolMethod.sublingual => dailyDoseMg == null ? null : dailyDoseMg! / 2,
      };

  /// "2 mg", or "2 mg · 0.4 mL" for an injection with a known strength.
  /// Null until the dose is set.
  String? get doseLabel {
    final mg = doseMg;
    if (mg == null) return null;
    final ml = method == EstradiolMethod.injection ? injectionVolumeMl : null;
    return ml == null ? '${formatDecimal(mg)} mg' : '${formatDecimal(mg)} mg · ${formatMl(ml)}';
  }

  static String formatMl(double ml) => '${formatDecimal(ml, maxDecimals: 3)} mL';

  /// The doses due on [date], in order.
  List<EstradiolSlot> slotsOn(DateTime date) => switch (method) {
        EstradiolMethod.injection => [?_injectionDays[date.weekday]],
        EstradiolMethod.oral => const [EstradiolSlot.morning],
        EstradiolMethod.sublingual => const [EstradiolSlot.morning, EstradiolSlot.evening],
      };

  /// "Wed AM, Fri PM, Sun AM"
  String get injectionDaysLabel =>
      [for (final e in _injectionDays.entries) '${_dayShort[e.key - 1]} ${e.value.short}'].join(', ');

  /// What the morning or evening time is used for; null when it isn't.
  String? timeUsage(EstradiolSlot slot) {
    switch (method) {
      case EstradiolMethod.injection:
        final days = [
          for (final e in _injectionDays.entries)
            if (e.value == slot) _dayLong[e.key - 1],
        ];
        if (days.isEmpty) return null;
        return '${days.join(' & ')} ${days.length == 1 ? 'injection' : 'injections'}';
      case EstradiolMethod.oral:
        return slot == EstradiolSlot.morning ? 'Daily oral dose' : null;
      case EstradiolMethod.sublingual:
        return slot == EstradiolSlot.morning ? 'Morning sublingual dose' : 'Evening sublingual dose';
    }
  }

  static const _unset = Object();

  EstradiolPlan copyWith({
    EstradiolMethod? method,
    Object? weeklyDoseMg = _unset,
    int? injectionsPerWeek,
    Object? strengthMgPerMl = _unset,
    Object? dailyDoseMg = _unset,
  }) =>
      EstradiolPlan(
        method: method ?? this.method,
        weeklyDoseMg: identical(weeklyDoseMg, _unset) ? this.weeklyDoseMg : weeklyDoseMg as double?,
        injectionsPerWeek: injectionsPerWeek ?? this.injectionsPerWeek,
        strengthMgPerMl: identical(strengthMgPerMl, _unset) ? this.strengthMgPerMl : strengthMgPerMl as double?,
        dailyDoseMg: identical(dailyDoseMg, _unset) ? this.dailyDoseMg : dailyDoseMg as double?,
      );

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'weeklyDoseMg': weeklyDoseMg,
        'injectionsPerWeek': injectionsPerWeek,
        'strengthMgPerMl': strengthMgPerMl,
        'dailyDoseMg': dailyDoseMg,
      };

  factory EstradiolPlan.fromJson(Map<String, dynamic> json) {
    double? positive(Object? v) => v is num && v > 0 ? v.toDouble() : null;
    final count = json['injectionsPerWeek'];
    return EstradiolPlan(
      method: EstradiolMethod.values.asNameMap()[json['method']] ?? EstradiolMethod.injection,
      weeklyDoseMg: positive(json['weeklyDoseMg']),
      injectionsPerWeek: count is int && injectionDays.containsKey(count) ? count : 3,
      strengthMgPerMl: positive(json['strengthMgPerMl']),
      dailyDoseMg: positive(json['dailyDoseMg']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EstradiolPlan &&
      other.method == method &&
      other.weeklyDoseMg == weeklyDoseMg &&
      other.injectionsPerWeek == injectionsPerWeek &&
      other.strengthMgPerMl == strengthMgPerMl &&
      other.dailyDoseMg == dailyDoseMg;

  @override
  int get hashCode => Object.hash(method, weeklyDoseMg, injectionsPerWeek, strengthMgPerMl, dailyDoseMg);
}

/// User-adjustable clock times (minutes after midnight) for the items the
/// protocol only describes loosely ("morning", "nightly", "evening").
class ReminderTimes {
  const ReminderTimes({
    this.estradiolMorning = 8 * 60,
    this.estradiolEvening = 20 * 60,
    this.progesterone = 22 * 60,
    this.powerPump = 19 * 60,
  });

  final int estradiolMorning;
  final int estradiolEvening;
  final int progesterone;
  final int powerPump;

  ReminderTimes copyWith({int? estradiolMorning, int? estradiolEvening, int? progesterone, int? powerPump}) =>
      ReminderTimes(
        estradiolMorning: estradiolMorning ?? this.estradiolMorning,
        estradiolEvening: estradiolEvening ?? this.estradiolEvening,
        progesterone: progesterone ?? this.progesterone,
        powerPump: powerPump ?? this.powerPump,
      );

  Map<String, dynamic> toJson() => {
        'estradiolMorning': estradiolMorning,
        'estradiolEvening': estradiolEvening,
        'progesterone': progesterone,
        'powerPump': powerPump,
      };

  factory ReminderTimes.fromJson(Map<String, dynamic> json) {
    const d = ReminderTimes();
    return ReminderTimes(
      estradiolMorning: json['estradiolMorning'] as int? ?? d.estradiolMorning,
      estradiolEvening: json['estradiolEvening'] as int? ?? d.estradiolEvening,
      progesterone: json['progesterone'] as int? ?? d.progesterone,
      powerPump: json['powerPump'] as int? ?? d.powerPump,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderTimes &&
      other.estradiolMorning == estradiolMorning &&
      other.estradiolEvening == estradiolEvening &&
      other.progesterone == progesterone &&
      other.powerPump == powerPump;

  @override
  int get hashCode => Object.hash(estradiolMorning, estradiolEvening, progesterone, powerPump);
}

class DomperidoneDose {
  const DomperidoneDose(this.minuteOfDay, this.mg);

  final int minuteOfDay;
  final int mg;

  int get tablets => mg ~/ Protocol.domperidoneTabletMg;
}

class KeyDate {
  const KeyDate(this.label, this.day);

  final String label;

  /// 1-based protocol day.
  final int day;
}

/// One timed item on a day's schedule.
class ScheduledEvent {
  const ScheduledEvent({
    required this.kind,
    required this.minuteOfDay,
    required this.title,
    required this.detail,
    this.timeLabel,
  });

  final EventKind kind;

  /// Minutes after the midnight that starts the protocol day. Overnight items
  /// (the midnight dose, the 3 AM pump) belong to the evening before, so they
  /// are 24:00 or later.
  final int minuteOfDay;
  final String title;
  final String detail;
  final String? timeLabel;

  String get time => timeLabel ?? formatMinuteOfDay(minuteOfDay);

  /// The wall-clock moment this event happens for the protocol day [date].
  DateTime at(DateTime date) => DateTime(date.year, date.month, date.day, 0, minuteOfDay);
}

class Protocol {
  Protocol._();

  // Phases
  static const buildDays = 40;
  static const birthDays = 2;

  // Key dates (1-based protocol days)
  static const domperidoneStepUpDay = 8; // second week: 20 / 10 / 20 mg
  static const fullDomperidoneDay = 15; // 2 weeks out
  static const lastProgesteroneDay = 40; // 40 days out
  static const pumpingStartDay = 41; // 41 days out
  static const powerPumpingStartDay = 56; // 56 days out

  // Doses
  static const domperidoneTabletMg = 10;
  /// Nightly progesterone until changed in Settings.
  static const double defaultProgesteroneMg = 300;

  /// Regular pumping sessions, 15–20 min each. 24:00 and 27:00 are midnight
  /// and the 3–4 AM session that close out the day.
  static const pumpTimes = [6 * 60, 9 * 60, 12 * 60, 15 * 60, 18 * 60, 21 * 60, 24 * 60, 27 * 60];
  static int get pumpSessionsPerDay => pumpTimes.length;

  static const powerPumpRoutine = ['Pump 20 min', 'Rest 10 min', 'Pump 10 min', 'Rest 10 min', 'Pump 10 min'];

  static const keyDates = [
    KeyDate('Start date', 1),
    KeyDate('Full domperidone dose', fullDomperidoneDay),
    KeyDate('Last progesterone dose', lastProgesteroneDay),
    KeyDate('Begin pumping', pumpingStartDay),
    KeyDate('Add power pumping', powerPumpingStartDay),
  ];

  /// 1-based protocol day for [date]; Day 1 is [start]. Null without a start.
  static int? dayNumber(DateTime? start, DateTime date) => start == null ? null : daysBetween(start, date) + 1;

  static DateTime dateForDay(DateTime start, int day) => addDays(start, day - 1);

  static Phase phaseForDay(int? day) {
    if (day == null || day < 1) return Phase.notStarted;
    if (day <= buildDays) return Phase.build;
    if (day <= buildDays + birthDays) return Phase.birth;
    return Phase.lactation;
  }

  static int phaseStartDay(Phase phase) => switch (phase) {
        Phase.notStarted => 0,
        Phase.build => 1,
        Phase.birth => buildDays + 1,
        Phase.lactation => buildDays + birthDays + 1,
      };

  /// Length of a fixed-length phase; null for open-ended phases.
  static int? phaseLength(Phase phase) => switch (phase) {
        Phase.build => buildDays,
        Phase.birth => birthDays,
        _ => null,
      };

  // ---- Domperidone ramp-up --------------------------------------------------

  static List<DomperidoneDose> domperidoneDoses(int day) {
    if (day < 1) return const [];
    if (day < domperidoneStepUpDay) {
      return const [DomperidoneDose(6 * 60, 10), DomperidoneDose(12 * 60, 10), DomperidoneDose(18 * 60, 10)];
    }
    if (day < fullDomperidoneDay) {
      return const [DomperidoneDose(6 * 60, 20), DomperidoneDose(12 * 60, 10), DomperidoneDose(18 * 60, 20)];
    }
    return const [
      DomperidoneDose(6 * 60, 20),
      DomperidoneDose(12 * 60, 20),
      DomperidoneDose(18 * 60, 20),
      DomperidoneDose(24 * 60, 20),
    ];
  }

  static int domperidoneTabletsForDay(int day) => domperidoneDoses(day).fold(0, (sum, d) => sum + d.tablets);

  static int domperidoneMgForDay(int day) => domperidoneDoses(day).fold(0, (sum, d) => sum + d.mg);

  // ---- Hormones -------------------------------------------------------------

  /// Estradiol doses due on protocol [day] ([date]) under [plan].
  static List<EstradiolSlot> estradiolSlots(int day, DateTime date, EstradiolPlan plan) =>
      day < 1 ? const [] : plan.slotsOn(date);

  /// Progesterone: nightly through Day 40.
  static bool progesteroneScheduled(int day) => day >= 1 && day <= lastProgesteroneDay;

  // ---- Pumping --------------------------------------------------------------

  static bool pumpingScheduled(int day) => day >= pumpingStartDay;

  static bool powerPumpingScheduled(int day) => day >= powerPumpingStartDay;

  // ---- Full daily schedule --------------------------------------------------

  static List<ScheduledEvent> eventsFor({
    required int day,
    required DateTime date,
    ReminderTimes times = const ReminderTimes(),
    EstradiolPlan estradiol = const EstradiolPlan(),
    double? progesteroneMg = defaultProgesteroneMg,
  }) {
    if (day < 1) return const [];
    final events = <ScheduledEvent>[];

    for (final dose in domperidoneDoses(day)) {
      events.add(ScheduledEvent(
        kind: EventKind.domperidone,
        minuteOfDay: dose.minuteOfDay,
        title: 'Domperidone ${dose.mg} mg',
        detail: '${dose.tablets} ${dose.tablets == 1 ? 'tablet' : 'tablets'}',
      ));
    }

    final estradiolDose = estradiol.doseMg;
    final estradiolMl = estradiol.method == EstradiolMethod.injection ? estradiol.injectionVolumeMl : null;
    for (final slot in estradiolSlots(day, date, estradiol)) {
      events.add(ScheduledEvent(
        kind: EventKind.estradiol,
        minuteOfDay: slot == EstradiolSlot.morning ? times.estradiolMorning : times.estradiolEvening,
        title: estradiolDose == null ? 'Estradiol' : 'Estradiol ${formatDecimal(estradiolDose)} mg',
        detail: [
          estradiol.method.label,
          if (estradiolMl != null) EstradiolPlan.formatMl(estradiolMl),
          if (estradiol.method != EstradiolMethod.oral) slot.label,
        ].join(' · '),
      ));
    }

    if (progesteroneScheduled(day)) {
      events.add(ScheduledEvent(
        kind: EventKind.progesterone,
        minuteOfDay: times.progesterone,
        title: progesteroneMg == null ? 'Progesterone' : 'Progesterone ${formatDecimal(progesteroneMg)} mg',
        detail: day == lastProgesteroneDay ? 'Nightly · last dose' : 'Nightly',
      ));
    }

    if (pumpingScheduled(day)) {
      for (final minute in pumpTimes) {
        events.add(ScheduledEvent(
          kind: EventKind.pump,
          minuteOfDay: minute,
          title: 'Pump session',
          detail: '15–20 min',
          timeLabel: minute == 27 * 60 ? '3–4 AM' : null,
        ));
      }
    }

    if (powerPumpingScheduled(day)) {
      events.add(ScheduledEvent(
        kind: EventKind.powerPump,
        minuteOfDay: times.powerPump,
        title: 'Power pumping',
        detail: powerPumpRoutine.join(' · '),
      ));
    }

    events.sort((a, b) {
      final byTime = a.minuteOfDay.compareTo(b.minuteOfDay);
      return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
    });
    return events;
  }
}
