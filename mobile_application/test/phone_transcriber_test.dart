import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/phone_transcriber.dart';

/// Words in lower case without punctuation, to compare a transcript with what was said.
List<String> _words(String text) => text.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Share of the spoken words the transcript got right, in order (word-level edit distance).
double _wordAccuracy(String said, String heard) {
  final a = _words(said);
  final b = _words(heard);
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      d[i][j] = math.min(math.min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
  }
  return 1 - d[a.length][b.length] / a.length;
}

void main() {
  group('getting a recording ready for the model', () {
    test('16-bit audio becomes floats between -1 and 1', () {
      final pcm = Uint8List(6);
      final view = ByteData.sublistView(pcm);
      view.setInt16(0, 0, Endian.little);
      view.setInt16(2, 16384, Endian.little);
      view.setInt16(4, -32768, Endian.little);
      final f = pcm16ToFloat(pcm);
      expect(f.length, 3);
      expect(f[0], 0);
      expect(f[1], closeTo(0.5, 1e-6));
      expect(f[2], -1.0);
    });

    test('made-up fragments are removed from the words, real words and numbers are kept', () {
      expect(cleanTranscript('I felt calm today. //'), 'I felt calm today.');
      expect(cleanTranscript('[BLANK_AUDIO]'), '');
      expect(cleanTranscript('['), '');
      expect(cleanTranscript('(music) I slept 7 hours [laughter] and it was fine.'), 'I slept 7 hours and it was fine.');
      expect(cleanTranscript("It's okay - I don't mind."), "It's okay I don't mind.");
      expect(cleanTranscript('   '), '');
    });

    test('quiet audio is silent, speech-level audio is not', () {
      expect(isSilent(Float32List(16000)), isTrue);
      expect(isSilent(Float32List.fromList(List.filled(16000, 0.001))), isTrue);
      expect(isSilent(Float32List.fromList(List.generate(16000, (i) => 0.2 * math.sin(i * 0.1)))), isFalse);
    });

    test('a short recording is left whole', () {
      final pieces = splitForWhisper(Float32List(16000 * 20));
      expect(pieces, hasLength(1));
    });

    test('a long recording is cut into pieces under 30 s that together are the whole recording', () {
      final samples = Float32List(16000 * 100);
      final pieces = splitForWhisper(samples);
      expect(pieces.length, greaterThanOrEqualTo(4));
      expect(pieces.every((p) => p.length <= 28 * 16000), isTrue);
      expect(pieces.fold<int>(0, (n, p) => n + p.length), samples.length);
    });

    test('it cuts in the quietest moment instead of through speech', () {
      // loud everywhere except a 300 ms pause about 25 s in
      final samples = Float32List(16000 * 40);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = 0.5 * math.sin(i * 0.05);
      }
      const pauseStart = 16000 * 25;
      for (var i = pauseStart; i < pauseStart + 4800; i++) {
        samples[i] = 0;
      }
      final first = splitForWhisper(samples).first;
      expect(first.length, inInclusiveRange(pauseStart, pauseStart + 4800));
    });
  });

  group('the real model on this computer', () {
    const modelDir = r'F:\__Downloads\envs\stt_models\sherpa-onnx-whisper-base.en';
    final scratch = Platform.environment['SOLACE_TEST_AUDIO_DIR'] ?? '';
    final transcriber = PhoneTranscriber(
      files: const WhisperModelFiles(modelDir),
      threads: 4,
      nativeLibraryPath: r'C:\Users\Rafsan Riasat\AppData\Local\Pub\Cache\hosted\pub.dev\sherpa_onnx_windows-1.13.8\windows',
    );
    final ready = transcriber.available && scratch.isNotEmpty && File('$scratch${Platform.pathSeparator}short.wav').existsSync();

    Uint8List pcmOf(String name) => File('$scratch${Platform.pathSeparator}$name').readAsBytesSync().sublist(44); // 44-byte WAV header

    test('writes down a short recording', () async {
      final sw = Stopwatch()..start();
      final text = await transcriber.transcribe(pcmOf('short.wav'));
      // ignore: avoid_print
      print('short (6 s) -> ${sw.elapsedMilliseconds} ms: "$text" codes-at-end: ${text?.codeUnits.reversed.take(4).toList()}');
      final said = File('$scratch${Platform.pathSeparator}short.txt').readAsStringSync();
      expect(text, isNotNull);
      expect(_wordAccuracy(said, text!), greaterThan(0.85));
    }, skip: ready ? false : 'model or test audio not present');

    test('writes down a long recording in pieces without losing the middle', () async {
      final sw = Stopwatch()..start();
      final text = await transcriber.transcribe(pcmOf('long.wav'));
      // ignore: avoid_print
      print('long (100 s) -> ${sw.elapsedMilliseconds} ms, ${text?.length} characters');
      final said = File('$scratch${Platform.pathSeparator}long.txt').readAsStringSync();
      expect(text, isNotNull);
      expect(_wordAccuracy(said, text!), greaterThan(0.85));
    }, skip: ready ? false : 'model or test audio not present', timeout: const Timeout(Duration(minutes: 5)));

    test('gives nothing for silence, and nothing when the model is missing', () async {
      expect(await PhoneTranscriber(files: const WhisperModelFiles(r'Z:\no\such\folder')).transcribe(Uint8List(64000)), isNull);
      if (transcriber.available) expect(await transcriber.transcribe(Uint8List(64000)), isNull);
    });
  });
}
