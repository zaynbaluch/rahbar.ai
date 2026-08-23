import 'package:flutter/material.dart';

import '../design_system/theme/app_colors.dart';
import '../design_system/theme/app_radii.dart';

/// Material 3 theme for Rahbar AI.
///
/// The brand palette is concentrated in actions, navigation, and status. Content
/// remains on neutral surfaces so long lesson plans and tests stay comfortable to read.
class RahbarTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.softBlue,
      onPrimaryContainer: AppColors.navy,
      secondary: AppColors.gold,
      onSecondary: AppColors.navy,
      secondaryContainer: AppColors.softGold,
      onSecondaryContainer: AppColors.warningText,
      tertiary: AppColors.success,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFDDF5E8),
      onTertiaryContainer: Color(0xFF0B5C33),
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFFE8E8),
      onErrorContainer: Color(0xFF7A1515),
      surface: AppColors.surface,
      onSurface: AppColors.text,
      surfaceContainerHighest: Color(0xFFF0F4FC),
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outline,
      outlineVariant: Color(0xFFE8EDF6),
      shadow: Color(0x1A0B1F5B),
      scrim: Color(0x660B1F5B),
      inverseSurface: AppColors.navy,
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFFAFC3FF),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: AppColors.text,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: AppColors.text,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: AppColors.text,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.outline),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.softBlue,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ).copyWith(
          overlayColor: const WidgetStatePropertyAll(Color(0x22FFFFFF)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.softBlue,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        labelStyle: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
    );
  }
}
