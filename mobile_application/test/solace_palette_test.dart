import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/core/theme/solace_palette.dart';

void main() {
  group('SolacePaletteId', () {
    test('resolves known ids', () {
      expect(
        SolacePaletteId.fromId('softTwilight'),
        SolacePaletteId.softTwilight,
      );
      expect(SolacePaletteId.fromId('warmCream'), SolacePaletteId.warmCream);
    });

    test('falls back to the default for unknown or missing ids', () {
      expect(SolacePaletteId.fromId('nonsense'), SolacePaletteId.warmCream);
      expect(SolacePaletteId.fromId(null), SolacePaletteId.warmCream);
    });

    test('palette ids stay unique and non-empty', () {
      final ids = SolacePaletteId.values.map((p) => p.id).toSet();
      expect(ids.length, SolacePaletteId.values.length);
      expect(ids.every((id) => id.isNotEmpty), isTrue);
    });
  });

  group('SolaceColors', () {
    test('palettes differ in neutrals but share accents', () {
      const warm = SolaceColors.warmCream;
      const twilight = SolaceColors.softTwilight;

      expect(warm.background, isNot(twilight.background));
      expect(warm.ink, isNot(twilight.ink));
      expect(warm.amber, twilight.amber);
      expect(warm.coral, twilight.coral);
    });

    test('of() maps ids to the matching palette', () {
      expect(
        SolaceColors.of(SolacePaletteId.softTwilight),
        SolaceColors.softTwilight,
      );
    });

    test('is registered on the theme and readable from context', () {
      final theme = AppTheme.light(palette: SolaceColors.softTwilight);

      expect(theme.extension<SolaceColors>(), SolaceColors.softTwilight);
      expect(theme.scaffoldBackgroundColor, SolaceColors.softTwilight.background);
    });

    testWidgets('from(context) reads the active palette', (tester) async {
      late SolaceColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(palette: SolaceColors.softTwilight),
          home: Builder(
            builder: (context) {
              resolved = SolaceColors.from(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, SolaceColors.softTwilight);
    });
  });
}
