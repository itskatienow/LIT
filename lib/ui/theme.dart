import 'package:flutter/material.dart';

import '../models/protocol.dart';

const _seed = Color(0xFF8E4A6B); // plum

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  // Start from the platform typography so custom styles keep its font family.
  final textTheme = ThemeData(colorScheme: scheme).textTheme;
  final fieldRadius = BorderRadius.circular(14);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      // Underline-style borders keep the floating label inside the fill.
      border: UnderlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      enabledBorder: UnderlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      focusedBorder: UnderlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
    ),
  );
}

Color phaseSeed(Phase phase) => switch (phase) {
      Phase.notStarted => const Color(0xFF7A7480),
      Phase.build => const Color(0xFF6A4FB3), // violet
      Phase.birth => const Color(0xFFD9653B), // coral
      Phase.lactation => const Color(0xFF2A8C82), // teal
    };

final _phaseSchemes = <(Phase, Brightness), ColorScheme>{};

ColorScheme phaseScheme(Phase phase, Brightness brightness) => _phaseSchemes.putIfAbsent(
      (phase, brightness),
      () => ColorScheme.fromSeed(seedColor: phaseSeed(phase), brightness: brightness),
    );

IconData phaseIcon(Phase phase) => switch (phase) {
      Phase.notStarted => Icons.hourglass_empty_rounded,
      Phase.build => Icons.trending_up_rounded,
      Phase.birth => Icons.child_care_rounded,
      Phase.lactation => Icons.water_drop_rounded,
    };

IconData eventIcon(EventKind kind) => switch (kind) {
      EventKind.domperidone => Icons.medication_outlined,
      EventKind.estradiol => Icons.vaccines_outlined,
      EventKind.progesterone => Icons.bedtime_outlined,
      EventKind.pump => Icons.water_drop_outlined,
      EventKind.powerPump => Icons.bolt_outlined,
    };
