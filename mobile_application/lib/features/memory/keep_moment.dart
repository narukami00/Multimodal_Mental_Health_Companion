import 'package:flutter/material.dart';

import '../../domain/memory/moment_entry.dart';
import '../insights/moments_tab.dart' show showAddMomentSheet;
import 'moments_controller.dart';

/// The way in to "keep this as a moment" from anywhere the person's own words are shown: a journal entry, or one of
/// their chat messages. Set once in main.dart; without it the buttons are simply not shown.
class KeepMoment {
  KeepMoment._();

  static MomentsController? controller;

  static bool get available => controller != null;

  /// Whether something from this entry or message is already kept.
  static bool isKept(String sourceRef) =>
      controller?.confirmed.any((m) => m.sourceRef == sourceRef) ?? false;

  /// Opens the sheet that offers the person's own best sentence from [entry] to keep.
  static Future<void> open(BuildContext context, MomentEntry entry) async {
    final moments = controller;
    if (moments == null) return;
    await showAddMomentSheet(context, moments, entry: entry);
  }
}
