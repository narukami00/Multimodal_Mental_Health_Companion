import 'face_reader.dart';
import 'face_reading_choice.dart';
import 'phone_transcriber.dart';
import 'stt_model_store.dart';

/// The app-wide on-phone camera models (reading the face on the phone), set once in `main.dart`.
class PhoneFace {
  PhoneFace._();

  static FaceModelStore store = FaceModelStore();

  /// The person's choice of where the face is read. The server by default.
  static FaceReadingChoice choice = FaceReadingChoice();

  /// The reader that runs the on-phone pipeline (loaded only when it is going to be used).
  static FaceReader reader = FaceReader();

  /// Whether the on-phone face pipeline exists in this build. When false the camera models are not offered, so nobody
  /// is asked to download something that does nothing.
  static bool pipelineReady = true;

  /// The folder of the camera models when the person chose the phone, the models are installed, and the phone can run
  /// them (Android 7 or newer). Null otherwise: the server then reads the face, as before.
  static Future<String?> directoryForPhoneReading() async {
    if (!pipelineReady || choice.place != FaceReadingPlace.phone) return null;
    return store.installedDirectory();
  }
}

/// The app-wide on-phone speech model, set once in `main.dart` (the same pattern as `KeepMoment`), so any page
/// can ask for "the phone's transcriber, if the model is installed" without being handed it.
class PhoneSpeech {
  PhoneSpeech._();

  static SttModelStore store = SttModelStore();

  /// A transcriber when the model is fully installed, else null.
  static Future<PhoneTranscriber?> transcriber() async {
    final files = await store.installed();
    return files == null ? null : PhoneTranscriber(files: files, threads: 2);
  }
}
