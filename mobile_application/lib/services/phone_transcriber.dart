import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// The three files of the on-phone Whisper model (the same family as the server's `base.en`).
class WhisperModelFiles {
  const WhisperModelFiles(this.directory);

  final String directory;

  static const encoderName = 'base.en-encoder.int8.onnx';
  static const decoderName = 'base.en-decoder.int8.onnx';
  static const tokensName = 'base.en-tokens.txt';
  static const all = [encoderName, decoderName, tokensName];

  String get encoder => '$directory${Platform.pathSeparator}$encoderName';
  String get decoder => '$directory${Platform.pathSeparator}$decoderName';
  String get tokens => '$directory${Platform.pathSeparator}$tokensName';

  bool get isComplete => all.every((n) => File('$directory${Platform.pathSeparator}$n').existsSync());
}

/// Cuts a recording into pieces Whisper can read (it takes at most 30 s at a time), preferably in the
/// quietest moment near the end of each piece so a word is never split. Pure and synchronous.
List<Float32List> splitForWhisper(
  Float32List samples, {
  int sampleRate = 16000,
  double maxSeconds = 28,
  double searchSeconds = 5,
}) {
  final max = (maxSeconds * sampleRate).round();
  if (samples.length <= max) return [samples];
  final window = sampleRate ~/ 10; // 100 ms
  final search = (searchSeconds * sampleRate).round();
  final pieces = <Float32List>[];
  var start = 0;
  while (samples.length - start > max) {
    final limit = start + max;
    var cut = limit;
    var quietest = double.infinity;
    for (var s = limit - search; s + window <= limit; s += window ~/ 2) {
      var energy = 0.0;
      for (var i = s; i < s + window; i++) {
        energy += samples[i] * samples[i];
      }
      if (energy < quietest) {
        quietest = energy;
        cut = s + window ~/ 2; // the middle of the quietest window
      }
    }
    pieces.add(Float32List.sublistView(samples, start, cut));
    start = cut;
  }
  pieces.add(Float32List.sublistView(samples, start));
  return pieces;
}

/// Whisper invents fragments on silence and after the last word ("[BLANK_AUDIO]", "(music)", "//", a lone "["). This
/// removes bracketed non-speech tags and any piece with no letter or digit in it, and tidies the spaces.
String cleanTranscript(String raw) {
  final noTags = raw.replaceAll(RegExp(r'\[[^\]]*\]?|\([^)]*\)'), ' ');
  final kept = noTags.split(RegExp(r'\s+')).where((w) => RegExp(r'[A-Za-z0-9]').hasMatch(w));
  return kept.join(' ').trim();
}

/// True when a piece of audio is too quiet to hold speech (below about -48 dBFS), so it is not worth decoding
/// and would only invite the model to make words up.
bool isSilent(Float32List samples, {double threshold = 0.004}) {
  if (samples.isEmpty) return true;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  return math.sqrt(sum / samples.length) < threshold;
}

/// 16-bit little-endian mono PCM to floats in [-1, 1].
Float32List pcm16ToFloat(Uint8List pcm) {
  final count = pcm.length ~/ 2;
  final view = ByteData.sublistView(pcm);
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Writes down a recording on the phone itself, with no server and no network.
///
/// The model runs in a background isolate, so the screen never freezes. It is loaded for each recording and
/// released straight after (about 150 MB of memory is only held while it works). Returns null, never throws,
/// when the model is missing or anything goes wrong: the caller then waits for the server instead.
class PhoneTranscriber {
  PhoneTranscriber({required this.files, this.threads = 2, this.nativeLibraryPath});

  final WhisperModelFiles files;
  final int threads;

  /// Only for running on a computer in tests; on the phone the library is bundled and found by itself.
  final String? nativeLibraryPath;

  bool get available => files.isComplete;

  /// The words, or null when nothing could be made. The audio must be 16 kHz mono (what the app records).
  Future<String?> transcribe(Uint8List pcm16) async {
    if (!available || pcm16.length < 16000 * 2) return null;
    final chunks = splitForWhisper(pcm16ToFloat(pcm16));
    final request = _Request(files.encoder, files.decoder, files.tokens, threads, chunks, nativeLibraryPath);
    try {
      final total = Stopwatch()..start();
      final result = await Isolate.run(() => _decode(request));
      final trimmed = result.text.trim();
      debugPrint('[PhoneTranscriber] ${(pcm16.length / 32000).toStringAsFixed(1)} s of audio in ${chunks.length} piece(s), '
          '$threads threads: ${total.elapsedMilliseconds} ms total (model load ${result.loadMs} ms, decode ${result.decodeMs} ms), '
          '${trimmed.length} characters');
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      debugPrint('[PhoneTranscriber] failed: ${e.runtimeType}: $e');
      return null;
    }
  }
}

class _Request {
  const _Request(this.encoder, this.decoder, this.tokens, this.threads, this.chunks, this.libraryPath);

  final String? libraryPath;
  final String encoder;
  final String decoder;
  final String tokens;
  final int threads;
  final List<Float32List> chunks;
}

({String text, int loadMs, int decodeMs}) _decode(_Request r) {
  final clock = Stopwatch()..start();
  final libraryPath = r.libraryPath;
  if (libraryPath != null && Platform.isWindows) {
    // Windows would otherwise pick its own, older onnxruntime.dll before the one next to the sherpa library.
    ffi.DynamicLibrary.open('$libraryPath${Platform.pathSeparator}onnxruntime.dll');
  }
  sherpa.initBindings(libraryPath);
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(encoder: r.encoder, decoder: r.decoder, language: 'en', task: 'transcribe'),
        tokens: r.tokens,
        modelType: 'whisper',
        numThreads: r.threads,
        debug: false,
      ),
    ),
  );
  final loadMs = clock.elapsedMilliseconds;
  try {
    final parts = <String>[];
    for (final chunk in r.chunks) {
      if (isSilent(chunk)) continue;
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: chunk, sampleRate: 16000);
        recognizer.decode(stream);
        final text = cleanTranscript(recognizer.getResult(stream).text);
        if (text.isNotEmpty) parts.add(text);
      } finally {
        stream.free();
      }
    }
    return (text: parts.join(' '), loadMs: loadMs, decodeMs: clock.elapsedMilliseconds - loadMs);
  } finally {
    recognizer.free();
  }
}
