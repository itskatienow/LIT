/// The lactation-induction protocol: phases, key dates, and the daily
/// medication and pumping schedule.
///
/// Days are numbered from 1: the start date is Day 1. Every protocol number
/// lives in [Protocol] so the plan can be adjusted in one place.
library;

import '../util/dates.dart';

enum Phase { notStarted, build, birth, lactation }

extension PhaseInfo on Phase {
  String get label => switch (this) {
        Phase.notStarted => 'Not started',
        Phase.build => 'Build',
        Phase.birth => 'Birth',
        Phase.lactation => 'Lactation',
      };
}

/// Things that appear on the daily schedule and can trigger a reminder.
enum EventKind { domperidone, estradiol, progesterone, pump, powerPump }

extension EventKindInfo on EventKind {
  String get label => switch (this) {
        EventKind.domperidone => 'Domperidone',
        EventKind.estradiol => 'Estradiol injections',
        EventKind.progesterone => 'Progesterone',
        EventKind.pump => 'Pumping sessions',
        EventKind.powerPump => 'Power pumping',
      };
}

enum EstradiolSlot { morning, evening }

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
  static const estradiolMg = 2;
  static const progesteroneMg = 300;

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

  /// Estradiol: Wednesday morning, Friday evening, Sunday morning.
  static EstradiolSlot? estradiolSlot(int day, DateTime date) {
    if (day < 1) return null;
    return switch (date.weekday) {
      DateTime.wednesday => EstradiolSlot.morning,
      DateTime.friday => EstradiolSlot.evening,
      DateTime.sunday => EstradiolSlot.morning,
      _ => null,
    };
  }

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

    final slot = estradiolSlot(day, date);
    if (slot != null) {
      events.add(ScheduledEvent(
        kind: EventKind.estradiol,
        minuteOfDay: slot == EstradiolSlot.morning ? times.estradiolMorning : times.estradiolEvening,
        title: 'Estradiol $estradiolMg mg',
        detail: slot == EstradiolSlot.morning ? 'Injection · morning' : 'Injection · evening',
      ));
    }

    if (progesteroneScheduled(day)) {
      events.add(ScheduledEvent(
        kind: EventKind.progesterone,
        minuteOfDay: times.progesterone,
        title: 'Progesterone $progesteroneMg mg',
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
