import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/forest/tree_geometry.dart';
import '../features/forest/forest_card_scene.dart' show geometryFor;
import '../features/forest/tree_painter.dart' show matureTreeOutline, paintTree;
import 'check_in_widget_service.dart';

/// Publishes the current tree as a transparent sprite. Android renders the
/// landscape independently so the widget can resize and change light on its own.
class ForestWidgetService {
  ForestWidgetService._();

  static final ForestWidgetService instance = ForestWidgetService._();

  // Matches CheckInWidgetProvider.KEY_TREE. Old scene files used a wide crop.
  static const treeKey = 'forest_tree_path';
  static const _size = 160.0;
  static const _density = 2.0;

  String? _lastSignature;
  Future<void> _pending = Future.value();

  @visibleForTesting
  static String signature({required int species, required double stage}) =>
      '$species|${(stage * 4).round()}';

  @visibleForTesting
  static Future<Uint8List> renderTree({
    required int species,
    required double stage,
  }) async {
    final tree = treeSpecies[species];
    final geometry = geometryFor(species);
    final crown = matureTreeOutline(geometry, revealAt(stage)).getBounds();
    final early = 1 - smooth(3.45, 4.7, stage);
    final halfWidth = math.max(32.0, math.max(-crown.left, crown.right) + 14);
    final height = math.max(48 + 39 * smooth(1, 3.2, stage), -crown.top + 20);
    final scale = math.min(70 / halfWidth, (114 + 26 * (1 - early)) / height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(_density)
      ..translate(_size / 2, _size - 19);
    final shadow = Rect.fromCenter(
      center: const Offset(0, 3),
      width: 44 + 38 * (1 - early),
      height: 10 + 6 * (1 - early),
    );
    canvas.drawOval(
      shadow,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x46213A29), Color(0x00213A29)],
        ).createShader(shadow),
    );
    canvas.scale(scale);
    paintTree(canvas, geometry, tree, stage, soil: true);

    final picture = recorder.endRecording();
    final pixels = (_size * _density).round();
    try {
      final image = await picture.toImage(pixels, pixels);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Serialize writes so a slower render cannot replace a newer tree.
  Future<void> push({required int species, required double stage}) {
    return _pending = _pending.then((_) async {
      final sig = signature(species: species, stage: stage);
      if (sig == _lastSignature) return;
      try {
        final dir = await getApplicationSupportDirectory();
        final path =
            '${dir.path}${Platform.pathSeparator}forest_widget_tree.png';
        final temporary = File('$path.tmp');
        await temporary.writeAsBytes(
          await renderTree(species: species, stage: stage),
          flush: true,
        );
        await temporary.rename(path);
        await HomeWidget.saveWidgetData<String>(treeKey, path);
        await HomeWidget.updateWidget(
          androidName: CheckInWidgetService.androidWidgetName,
        );
        _lastSignature = sig;
      } catch (error) {
        debugPrint('ForestWidgetService warning: $error');
      }
    });
  }
}
