import 'dart:async';

import 'package:flutter/services.dart';

import 'video_frame_service.dart';

/// Where the live self view is: a Flutter texture fed by the camera's own
/// preview at its normal frame rate, and how the buffer is turned.
class CameraPreviewInfo {
  const CameraPreviewInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final int textureId;

  /// Size of the camera buffer, in the sensor's orientation.
  final int width;
  final int height;

  /// Clockwise degrees to turn the buffer so it is upright.
  final int rotation;
}

/// The phone's front camera as a [FrameSource]: upright JPEG frames from the
/// native CameraX capture (`CameraFrameCapture.kt`), about five per second, for
/// the server. The person's own view is separate: see [previewInfo].
///
/// Starting it asks Android for the CAMERA permission if it is missing (that
/// system prompt is the only place the permission is requested) and returns
/// false when the person says no or the camera cannot be opened. Frames are
/// held in memory only.
class PlatformFrameSource implements FrameSource {
  PlatformFrameSource({
    MethodChannel? control,
    EventChannel? stream,
  })  : _control = control ??
            const MethodChannel('com.sysmentalhealth.solace_mobile/camera_control'),
        _stream = stream ??
            const EventChannel('com.sysmentalhealth.solace_mobile/camera_stream');

  final MethodChannel _control;
  final EventChannel _stream;

  @override
  Stream<Uint8List> get frames => _stream
      .receiveBroadcastStream()
      .where((event) => event is Uint8List)
      .cast<Uint8List>();

  /// Where the smooth live self view is, or null when there is none (the camera
  /// is closed, still opening, or there is no native side).
  Future<CameraPreviewInfo?> previewInfo() async {
    try {
      final raw = await _control.invokeMapMethod<String, Object?>('previewInfo');
      if (raw == null) return null;
      final id = raw['textureId'];
      final w = raw['width'];
      final h = raw['height'];
      final r = raw['rotation'];
      if (id is! num || w is! num || h is! num || r is! num) return null;
      return CameraPreviewInfo(
        textureId: id.toInt(),
        width: w.toInt(),
        height: h.toInt(),
        rotation: r.toInt(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether Android already granted the camera permission (no prompt).
  Future<bool> hasPermission() async {
    try {
      return await _control.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> start() async {
    try {
      return await _control.invokeMethod<bool>('start') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _control.invokeMethod<bool>('stop');
    } on PlatformException {
      // Already closed.
    } on MissingPluginException {
      // No native side (tests, other platforms).
    }
  }
}
