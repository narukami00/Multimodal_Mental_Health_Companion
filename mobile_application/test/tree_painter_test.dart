import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/domain/forest/tree_geometry.dart';
import 'package:solace_mobile/features/forest/tree_painter.dart';

void main() {
  test('every species draws at every stage without trouble, and leaves something to see once it is a tree', () async {
    for (final sp in treeSpecies) {
      final geo = generateTree(4242, sp);
      for (final s in [0.0, 0.5, 1.2, 2.0, 2.6, 3.2, 3.8, 4.5, 5.5, 6.4, 7.0]) {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 300, 300));
        canvas.translate(150, 280);
        paintTree(canvas, geo, sp, s, soil: s < 7);
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 300);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        var painted = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] > 0) painted++;
        }
        expect(painted, greaterThan(0), reason: '${sp.name} at stage $s drew nothing');
        if (s >= 7) expect(painted, greaterThan(4000), reason: '${sp.name} fully grown should fill a good part of the picture');
      }
    }
  });

  test('the watering can draws', () async {
    final recorder = PictureRecorder();
    paintWateringCan(Canvas(recorder, const Rect.fromLTWH(0, 0, 80, 60))..translate(40, 30));
    final image = await recorder.endRecording().toImage(80, 60);
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    expect([for (var i = 3; i < bytes.length; i += 4) bytes[i]].any((a) => a > 0), isTrue);
  });
}
