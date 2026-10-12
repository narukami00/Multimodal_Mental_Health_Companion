import 'dart:async';

import 'package:flutter/services.dart';

import 'video_frame_service.dart';

/// The phone's front camera as a [FrameSource]: upright JPEG frames from the
/// native CameraX capture (`CameraFrameCapture.kt`), about five per second.
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
