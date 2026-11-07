import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../features/forest/forest_card_scene.dart';

/// The tiny forest on the home-screen widget: the same sky and growing tree as the check-in card, drawn once into a
/// picture and handed to the widget, which lays its words and buttons on top.
///
/// A widget cannot run an animation of its own, so it is redrawn when something visible changes: the tree's stage,
/// which tree it is, or the light of the hour (day, golden, dusk, night). Nothing here counts or rewards.
class ForestWidgetService {
  ForestWidgetService._();

  static final ForestWidgetService instance = ForestWidgetService._();

  /// Must match the Kotlin provider's `KEY_SCENE`.
  static const sceneKey = 'forest_scene_path';

  /// The drawn size: what the card painter is laid out for, drawn at twice the density.
  static const logicalSize = Size(340, 120);
  static const density = 2.0;

  String? _lastSignature;

  /// What the widget would show, as a string: pushing is skipped when it has not changed.
  static String signature({required ForestPalette palette, required int species, required double stage, required bool waterWaiting}) =>
      '${palette.name}|$species|${(stage * 2).round()}|$waterWaiting';

  /// The scene as PNG bytes: the orange of the card melting into the sky of the hour, and the tree. The corners are
  /// rounded to match the widget's card, so the widget needs no clipping of its own.
  static Future<Uint8List> renderScene({
    required ForestPalette palette,
    required int species,
    required double stage,
    required bool waterWaiting,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & Size(logicalSize.width * density, logicalSize.height * density));
    canvas.scale(density);
    final full = Offset.zero & logicalSize;
    canvas.clipRRect(RRect.fromRectAndRadius(full, const Radius.circular(34)));
    canvas.drawRect(
      full,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(logicalSize.width, logicalSize.height), palette.left, [0, .5, 1]),
    );
    ForestCardPainter(palette: palette, species: species, stage: stage, waterWaiting: waterWaiting).paint(canvas, logicalSize);
    final image = await recorder.endRecording().toImage(
      (logicalSize.width * density).round(),
      (logicalSize.height * density).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Draws the scene and tells the widget. Contained: a widget that cannot refresh never disturbs the app.
  Future<void> push({
    required ForestPalette palette,
    required int species,
    required double stage,
    required bool waterWaiting,
  }) async {
    final sig = signature(palette: palette, species: species, stage: stage, waterWaiting: waterWaiting);
    if (sig == _lastSignature) return;
    try {
      final bytes = await renderScene(palette: palette, species: species, stage: stage, waterWaiting: waterWaiting);
      final dir = await getApplicationSupportDirectory();
      // A new file name each time the picture changes, so the widget never shows a cached older one.
      final file = File('${dir.path}${Platform.pathSeparator}forest_widget_${sig.hashCode.toUnsigned(32)}.png');
      await file.writeAsBytes(bytes, flush: true);
      for (final old in dir.listSync().whereType<File>()) {
        if (old.path != file.path && old.uri.pathSegments.last.startsWith('forest_widget_')) {
          try {
            old.deleteSync();
          } catch (_) {}
        }
      }
      await HomeWidget.saveWidgetData<String>(sceneKey, file.path);
      await HomeWidget.updateWidget(androidName: 'CheckInWidgetProvider');
      _lastSignature = sig;
    } catch (error) {
      debugPrint('ForestWidgetService warning: $error');
    }
  }
}
