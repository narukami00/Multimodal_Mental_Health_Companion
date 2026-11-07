import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/tree_geometry.dart';

/// The reference numbers come from the approved JavaScript prototype (forest_prototype_v2.html), run in Node, so the app
/// draws exactly the trees that were approved.
void main() {
  final ref = jsonDecode(File('test/fixtures/forest/tree_reference.json').readAsStringSync()) as Map<String, dynamic>;

  test('the random generator matches the prototype', () {
    final r = mulberry32(4255);
    final expected = (ref['rng'] as List).cast<num>();
    for (final e in expected) {
      expect(r(), closeTo(e.toDouble(), 1e-12));
    }
  });

  group('every species grows the same tree as the prototype', () {
    final species = ref['species'] as Map<String, dynamic>;
    for (var i = 0; i < treeSpecies.length; i++) {
      final sp = treeSpecies[i];
      test(sp.name, () {
        final want = species[sp.key] as Map<String, dynamic>;
        final g = generateTree(want['seed'] as int, sp);
        expect(g.segs.length, want['segs']);
        expect(g.clumps.length, want['clumps']);
        expect(g.tiers.length, want['tiers']);
        expect(g.strands.length, want['strands']);
        expect(g.bark.length, want['bark']);
        expect(g.roots.length, want['roots']);
        expect(g.touches.length, want['touches']);
        expect(g.height, closeTo((want['height'] as num).toDouble(), 1e-6));
        expect(g.halfW, closeTo((want['halfW'] as num).toDouble(), 1e-6));
        expect(g.crownTop, closeTo((want['crownTop'] as num).toDouble(), 1e-6));
        expect(g.crownBot, closeTo((want['crownBot'] as num).toDouble(), 1e-6));
        final s0 = want['seg0'] as Map<String, dynamic>;
        expect(g.segs.first.x1, closeTo((s0['x1'] as num).toDouble(), 1e-6));
        expect(g.segs.first.w0, closeTo((s0['w0'] as num).toDouble(), 1e-6));
        final c3 = want['clump3'] as Map<String, dynamic>?;
        if (c3 != null) {
          expect(g.clumps[3].x, closeTo((c3['x'] as num).toDouble(), 1e-6));
          expect(g.clumps[3].r, closeTo((c3['R'] as num).toDouble(), 1e-6));
          expect(g.clumps[3].blobs.length, c3['blobs']);
        }
      });
    }
  });

  test('what is revealed follows the stage, like the prototype', () {
    final reveal = ref['reveal'] as Map<String, dynamic>;
    for (final entry in reveal.entries) {
      final want = entry.value as Map<String, dynamic>;
      final got = revealAt(double.parse(entry.key));
      expect(got.rr, closeTo((want['rr'] as num).toDouble(), 1e-9), reason: 'stage ${entry.key}');
      expect(got.sc, closeTo((want['sc'] as num).toDouble(), 1e-9));
      expect(got.thick, closeTo((want['thick'] as num).toDouble(), 1e-9));
      expect(got.tree, closeTo((want['tree'] as num).toDouble(), 1e-9));
      expect(got.seedling, closeTo((want['seedling'] as num).toDouble(), 1e-9));
    }
  });
}
