/// Everything logged for one calendar day.
class DayEntry {
  const DayEntry({
    this.estradiolDoses = 0,
    this.progesteroneTaken = false,
    this.domperidoneTablets = 0,
    this.pumped = false,
    this.pumpSessions = 0,
    this.powerPumped = false,
    this.outputMl,
    this.notes = '',
  });

  static const empty = DayEntry();

  /// Estradiol doses taken: 0 or 1, or up to 2 when sublingual.
  final int estradiolDoses;
  final bool progesteroneTaken;

  /// 10 mg tablets taken.
  final int domperidoneTablets;

  final bool pumped;
  final int pumpSessions;
  final bool powerPumped;

  /// Total output for the day; null when not entered.
  final double? outputMl;

  final String notes;

  // Pumping details stay saved if "Pumped" is switched off (so switching it
  // back on restores them), but they only count while it is on.
  int get countedSessions => pumped ? pumpSessions : 0;
  bool get countedPowerPump => pumped && powerPumped;
  double? get countedOutputMl => pumped ? outputMl : null;

  bool get isEmpty =>
      estradiolDoses == 0 &&
      !progesteroneTaken &&
      domperidoneTablets == 0 &&
      !pumped &&
      pumpSessions == 0 &&
      !powerPumped &&
      outputMl == null &&
      notes.trim().isEmpty;

  DayEntry copyWith({
    int? estradiolDoses,
    bool? progesteroneTaken,
    int? domperidoneTablets,
    bool? pumped,
    int? pumpSessions,
    bool? powerPumped,
    double? outputMl,
    bool clearOutput = false,
    String? notes,
  }) =>
      DayEntry(
        estradiolDoses: estradiolDoses ?? this.estradiolDoses,
        progesteroneTaken: progesteroneTaken ?? this.progesteroneTaken,
        domperidoneTablets: domperidoneTablets ?? this.domperidoneTablets,
        pumped: pumped ?? this.pumped,
        pumpSessions: pumpSessions ?? this.pumpSessions,
        powerPumped: powerPumped ?? this.powerPumped,
        outputMl: clearOutput ? null : (outputMl ?? this.outputMl),
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        // 'estradiol' stays so older versions of LIT can still read it.
        'estradiol': estradiolDoses > 0,
        if (estradiolDoses > 0) 'estradiolDoses': estradiolDoses,
        'progesterone': progesteroneTaken,
        'domperidone': domperidoneTablets,
        'pumped': pumped,
        'sessions': pumpSessions,
        'powerPumped': powerPumped,
        if (outputMl != null) 'outputMl': outputMl,
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory DayEntry.fromJson(Map<String, dynamic> json) => DayEntry(
        estradiolDoses: (json['estradiolDoses'] as num?)?.toInt() ?? (json['estradiol'] == true ? 1 : 0),
        progesteroneTaken: json['progesterone'] as bool? ?? false,
        domperidoneTablets: (json['domperidone'] as num?)?.toInt() ?? 0,
        pumped: json['pumped'] as bool? ?? false,
        pumpSessions: (json['sessions'] as num?)?.toInt() ?? 0,
        powerPumped: json['powerPumped'] as bool? ?? false,
        outputMl: (json['outputMl'] as num?)?.toDouble(),
        notes: json['notes'] as String? ?? '',
      );
}
