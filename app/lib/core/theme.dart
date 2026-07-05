import 'package:flutter/material.dart';

/// Central Material 3 theme for Rahbar AI.
///
/// Kept intentionally small for now; the polished design system comes in the
/// UX phase (see docs/07-3week-plan.md, Week 3).
class RahbarTheme {
  static const _seed = Color(0xFF1B6C4A); // green — evokes learning/growth

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: _seed);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
