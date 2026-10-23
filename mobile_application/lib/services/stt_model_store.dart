import 'dart:io';

import 'model_pack_store.dart';
import 'phone_transcriber.dart';

/// The on-phone speech model (Whisper `base.en`, about 153 MB): a [ModelPackStore] for the server's "stt" pack.
class SttModelStore extends ModelPackStore {
  SttModelStore({super.directory, super.serverBase})
      : super(pack: 'stt', files: WhisperModelFiles.all, folderName: 'whisper-base.en');

  /// What the app tells the person the download costs.
  static const approximateMegabytes = 153;

  /// The model's files when it is fully installed, else null.
  Future<WhisperModelFiles?> installed() async {
    final path = await installedDirectory();
    return path == null ? null : WhisperModelFiles(path);
  }
}

/// The on-phone camera models (about 19 MB), for reading the face on the phone itself: the server's "face" pack.
class FaceModelStore extends ModelPackStore {
  FaceModelStore({super.directory, super.serverBase})
      : super(pack: 'face', files: faceFileNames, folderName: 'face-v1');

  static const encoderName = 'b0_fp32.onnx';
  static const detectorName = 'face_detection_yunet_2023mar.onnx';
  static const landmarkerName = 'face_landmarker.task';
  static const faceFileNames = [encoderName, detectorName, landmarkerName];

  /// What the app tells the person the download costs.
  static const approximateMegabytes = 19;

  String path(String directory, String name) => '$directory${Platform.pathSeparator}$name';
}
