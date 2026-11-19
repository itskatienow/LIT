import 'package:flutter/material.dart';

import '../models/protocol.dart';

// One pink ramp, a step darker for each phase.
const _blush = Color(0xFFF4E4EB); // not started
const _lightPink = Color(0xFFF7B3CC); // Prime
const _rose = Color(0xFFE7779F); // Switch
const _deepPink = Color(0xFFC2316F); // Supply
const _ink = Color(0xFF3D0A24); // text on the lighter pinks

ColorScheme _appScheme(Brightness brightness) {
  final seeded = ColorScheme.fromSeed(seedColor: _deepPink, brightness: brightness);
  // Tonal fills (nav indicator, selected segments, info boxes) use the pink
  // container tones; the derived secondary is a muddy mauve in dark mode.
  final base = seeded.copyWith(
    secondaryContainer: seeded.primaryContainer,
    onSecondaryContainer: seeded.onPrimaryContainer,
  );
  // The accent (toggles, labels, buttons) is the deep pink on light
  // backgrounds and the light pink on dark ones.
  return brightness == Brightness.light
      ? base.copyWith(primary: _deepPink, onPrimary: Colors.white)
      : base.copyWith(primary: _lightPink, onPrimary: _ink);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = _appScheme(brightness);
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

/// The phase's pink, the same in light and dark mode.
Color phaseColor(Phase phase) => switch (phase) {
      Phase.notStarted => _blush,
      Phase.build => _lightPink,
      Phase.birth => _rose,
      Phase.lactation => _deepPink,
    };

/// Text and icon colour for content drawn on [phaseColor].
Color onPhaseColor(Phase phase) => phase == Phase.lactation ? Colors.white : _ink;

IconData phaseIcon(Phase phase) => switch (phase) {
      Phase.notStarted => Icons.hourglass_empty_rounded,
      Phase.build => Icons.trending_up_rounded,
      Phase.birth => Icons.swap_horiz_rounded,
      Phase.lactation => Icons.water_drop_rounded,
    };

IconData eventIcon(EventKind kind) => switch (kind) {
      EventKind.domperidone => Icons.medication_outlined,
      EventKind.estradiol => Icons.vaccines_outlined,
      EventKind.progesterone => Icons.bedtime_outlined,
      EventKind.pump => Icons.water_drop_outlined,
      EventKind.powerPump => Icons.bolt_outlined,
    };
