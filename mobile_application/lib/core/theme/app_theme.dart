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
      onSecondary: const Color(0xFF3D2E14),
      surface: palette.background,
      onSurface: palette.ink,
    );
    final actionShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const actionSize = Size(0, 48);
    const actionPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    const actionText = TextStyle(fontSize: 14, fontWeight: FontWeight.w800);
    final filledAction = FilledButton.styleFrom(
      backgroundColor: palette.amber,
      foregroundColor: AppColors.deepAmber,
      disabledBackgroundColor: palette.ink.withValues(alpha: .09),
      disabledForegroundColor: palette.ink.withValues(alpha: .45),
      minimumSize: actionSize,
      padding: actionPadding,
      textStyle: actionText,
      shape: actionShape,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      // Pages slide in solid. The default Android transition fades the new page in over the old one, so for a
      // moment the page looks like a ghostly overlay before it appears, which read as lag on heavier pages.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
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
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF81530C),
          minimumSize: actionSize,
          padding: actionPadding,
          textStyle: actionText,
          shape: actionShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filledAction),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: filledAction.copyWith(elevation: const WidgetStatePropertyAll(0)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: palette.surface,
          foregroundColor: palette.ink,
          disabledForegroundColor: palette.ink.withValues(alpha: .45),
          minimumSize: actionSize,
          padding: actionPadding,
          textStyle: actionText,
          shape: actionShape,
          side: BorderSide(color: palette.ink.withValues(alpha: .22)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? palette.surface : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) {
            if (states.contains(WidgetState.disabled)) return palette.ink.withValues(alpha: .13);
            return states.contains(WidgetState.selected) ? palette.amber : Color.lerp(palette.surface, palette.ink, .25);
          },
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: palette.surface.withValues(alpha: 0.82),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface.withValues(alpha: 0.92),
        indicatorColor: palette.amber.withValues(alpha: 0.22),
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
