import 'package:flutter/material.dart';

/// Colour palettes the user can choose from the You tab.
///
/// Only the neutrals change between palettes: the amber and coral accents
/// stay fixed so contrast and brand feel stay consistent.
enum SolacePaletteId {
  warmCream('warmCream', 'Warm Cream', 'The Solace default'),
  softTwilight('softTwilight', 'Soft Twilight', 'Cooler evening tones');

  const SolacePaletteId(this.id, this.label, this.description);

  /// Stable identifier persisted in the user profile.
  final String id;
  final String label;
  final String description;

  /// Resolves a stored id, falling back to the default palette.
  static SolacePaletteId fromId(String? id) {
    return values.firstWhere(
      (palette) => palette.id == id,
      orElse: () => SolacePaletteId.warmCream,
    );
  }
}

/// Theme extension holding the active surface, background and ink colours.
///
/// Pages read these instead of hardcoded literals so switching palette
/// actually re-themes the app.
@immutable
class SolaceColors extends ThemeExtension<SolaceColors> {
  const SolaceColors({
    required this.background,
    required this.surface,
    required this.ink,
    required this.mutedInk,
    required this.amber,
    required this.coral,
  });

  final Color background;
  final Color surface;
  final Color ink;
  final Color mutedInk;
  final Color amber;
  final Color coral;

  /// Current default palette: warm cream with amber and coral accents.
  static const warmCream = SolaceColors(
    background: Color(0xFFFEFCE8),
    surface: Colors.white,
    ink: Color(0xFF4A3728),
    mutedInk: Color(0xFF7B6A55),
    amber: Color(0xFFFFB534),
    coral: Color(0xFFFF7F50),
  );

  /// Evening palette: same accents, cooler neutral surfaces.
  static const softTwilight = SolaceColors(
    background: Color(0xFFF4F1FA),
    surface: Color(0xFFFBFAFF),
    ink: Color(0xFF3A3550),
    mutedInk: Color(0xFF7A7590),
    amber: Color(0xFFFFB534),
    coral: Color(0xFFFF7F50),
  );

  /// Resolves the colours for a palette id.
  static SolaceColors of(SolacePaletteId id) {
    return switch (id) {
      SolacePaletteId.warmCream => warmCream,
      SolacePaletteId.softTwilight => softTwilight,
    };
  }

  /// Convenience lookup from the theme, with a safe default.
  static SolaceColors from(BuildContext context) {
    return Theme.of(context).extension<SolaceColors>() ?? warmCream;
  }

  @override
  SolaceColors copyWith({
    Color? background,
    Color? surface,
    Color? ink,
    Color? mutedInk,
    Color? amber,
    Color? coral,
  }) {
    return SolaceColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      mutedInk: mutedInk ?? this.mutedInk,
      amber: amber ?? this.amber,
      coral: coral ?? this.coral,
    );
  }

  @override
  SolaceColors lerp(ThemeExtension<SolaceColors>? other, double t) {
    if (other is! SolaceColors) return this;
    return SolaceColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      mutedInk: Color.lerp(mutedInk, other.mutedInk, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
    );
  }
}
