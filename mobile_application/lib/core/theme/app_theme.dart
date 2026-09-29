import 'package:flutter/material.dart';

import 'solace_palette.dart';

/// Brand accent constants kept for legacy call sites.
///
/// New code should prefer [SolaceColors] from the theme so it follows the
/// user's selected palette.
abstract final class AppColors {
  static const amber = Color(0xFFFFB534);
  static const coral = Color(0xFFFF7F50);
  static const cream = Color(0xFFFEFCE8);
  static const ink = Color(0xFF4A3728);
  static const mutedInk = Color(0xFF7B6A55);
  static const deepAmber = Color(0xFF5C3A12);
}

abstract final class AppTheme {
  /// Builds the app theme for the selected [palette].
  static ThemeData light({SolaceColors palette = SolaceColors.warmCream}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.amber,
      brightness: Brightness.light,
    ).copyWith(
      primary: palette.amber,
      onPrimary: AppColors.deepAmber,
      secondary: palette.coral,
      onSecondary: Colors.white,
      surface: palette.background,
      onSurface: palette.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      fontFamily: 'Nunito',
      extensions: [palette],
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: palette.ink,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          color: palette.ink,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(
          color: palette.ink,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: palette.mutedInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface.withValues(alpha: 0.82),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface.withValues(alpha: 0.92),
        indicatorColor: palette.amber.withValues(alpha: 0.22),
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.amber,
          foregroundColor: AppColors.deepAmber,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
