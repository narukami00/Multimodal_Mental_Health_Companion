import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/platform_frame_source.dart';
import '../../services/video_frame_service.dart';

/// The person's own camera, as a mirror.
///
/// The server reads about five frames a second, but that is no reason to show
/// the person themselves at five frames a second. When the phone camera is the
/// source, this shows the camera's own live preview (a texture, at the camera's
/// normal rate), turned upright and flipped like a mirror. Without a live
/// preview (tests, other platforms, or while the camera is still opening) it
/// shows the latest analysis frame, flipped the same way.
class SelfView extends StatefulWidget {
  const SelfView({
    required this.source,
    required this.active,
    this.fallbackFrame,
    this.fallbackListenable,
    this.fallbackKey,
    this.placeholder,
    super.key,
  });

  /// Where frames come from. Only a [PlatformFrameSource] has a live preview.
  final FrameSource? source;

  /// Whether the camera is on. The preview is looked for when this becomes true.
  final bool active;

  /// The latest analysis frame, for when there is no live preview.
  final Uint8List? fallbackFrame;
  final ValueListenable<Uint8List?>? fallbackListenable;

  /// Key given to the fallback image, so it can be found.
  final Key? fallbackKey;

  /// Shown while there is nothing at all to show yet.
  final Widget? placeholder;

  @override
  State<SelfView> createState() => _SelfViewState();
}

class _SelfViewState extends State<SelfView> {
  CameraPreviewInfo? _info;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_look());
  }

  @override
  void didUpdateWidget(SelfView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      unawaited(_look());
    } else if (!widget.active && old.active) {
      setState(() => _info = null);
    }
  }

  /// The texture appears a moment after the camera opens, so ask a few times.
  Future<void> _look() async {
    final source = widget.source;
    if (source is! PlatformFrameSource || _looking) return;
    _looking = true;
    try {
      for (var i = 0; i < 20 && mounted && widget.active; i++) {
        final info = await source.previewInfo();
        if (info != null) {
          if (mounted) setState(() => _info = info);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _looking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info != null && widget.active) return _mirroredTexture(info);
    final listenable = widget.fallbackListenable;
    if (listenable != null) {
      return ValueListenableBuilder<Uint8List?>(
        valueListenable: listenable,
        builder: (context, frame, _) => _fallback(frame),
      );
    }
    return _fallback(widget.fallbackFrame);
  }

  Widget _fallback(Uint8List? frame) {
    if (frame == null) return widget.placeholder ?? const SizedBox.shrink();
    return Transform.flip(
      flipX: true,
      child: Image.memory(frame, key: widget.fallbackKey, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }

  /// Flutter draws the camera's texture already turned upright, so it only needs
  /// sizing (the buffer is reported in the sensor's landscape orientation) and
  /// flipping, like a mirror: a movement to the left looks like a movement to the
  /// left.
  Widget _mirroredTexture(CameraPreviewInfo info) {
    final sideways = info.rotation % 180 != 0;
    final width = (sideways ? info.height : info.width).toDouble();
    final height = (sideways ? info.width : info.height).toDouble();
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: Transform.flip(
            flipX: true,
            child: Texture(textureId: info.textureId),
          ),
        ),
      ),
    );
  }
}
