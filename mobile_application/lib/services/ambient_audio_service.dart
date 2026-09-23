import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Professional, clean ambient soundtrack definitions (no emojis).
enum SoundscapeMode {
  none('Off'),
  rain('Rainfall'),
  hearth('Campfire'),
  wind('Forest Wind'),
  solfeggio('Deep Stillness');

  const SoundscapeMode(this.label);
  final String label;
}

/// Global persistent audio service managing ambient soundtracks across the app lifecycle.
class AmbientAudioService {
  AmbientAudioService._();
  static final AmbientAudioService instance = AmbientAudioService._();

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<SoundscapeMode> currentModeNotifier =
      ValueNotifier<SoundscapeMode>(SoundscapeMode.none);

  SoundscapeMode get currentMode => currentModeNotifier.value;

  final Map<SoundscapeMode, String> _cachedPaths = {};
  bool _isInitialized = false;

  Future<void> _init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.72);
    } catch (e) {
      debugPrint('AmbientAudioService init warning: $e');
    }
  }

  /// Toggles the soundtrack on or off. If the tapped track is active, turns it off.
  Future<void> toggleSound(SoundscapeMode mode) async {
    if (currentMode == mode) {
      await stop();
    } else {
      await play(mode);
    }
  }

  /// Plays a specific ambient soundtrack in a continuous loop.
  Future<void> play(SoundscapeMode mode) async {
    if (mode == SoundscapeMode.none) {
      await stop();
      return;
    }

    await _init();
    currentModeNotifier.value = mode;

    try {
      final filePath = await _getOrGenerateWav(mode);
      if (filePath != null && File(filePath).existsSync()) {
        await _player.stop();
        await _player.play(DeviceFileSource(filePath));
      } else {
        final bytes = _synthesizeWav(mode);
        await _player.stop();
        await _player.play(BytesSource(bytes));
      }
    } catch (e) {
      debugPrint('AmbientAudioService play error for $mode: $e');
    }
  }

  /// Stops audio playback.
  Future<void> stop() async {
    currentModeNotifier.value = SoundscapeMode.none;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('AmbientAudioService stop error: $e');
    }
  }

  Future<String?> _getOrGenerateWav(SoundscapeMode mode) async {
    if (_cachedPaths.containsKey(mode)) {
      final path = _cachedPaths[mode]!;
      if (File(path).existsSync()) return path;
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/solace_ambient_${mode.name}.wav');
      if (!file.existsSync() || file.lengthSync() < 5000) {
        final bytes = _synthesizeWav(mode);
        await file.writeAsBytes(bytes, flush: true);
      }
      _cachedPaths[mode] = file.path;
      return file.path;
    } catch (e) {
      debugPrint('AmbientAudioService file cache error: $e');
      return null;
    }
  }

  /// Generates a mathematically seamless, pleasant 8-second 22050Hz 16-bit PCM WAV.
  static Uint8List _synthesizeWav(SoundscapeMode mode) {
    const sampleRate = 22050;
    const durationSeconds = 8.0;
    final totalSamples = (sampleRate * durationSeconds).toInt();
    final samples = List<double>.filled(totalSamples, 0.0);
    final rng = math.Random(mode.index * 1337 + 42);

    switch (mode) {
      case SoundscapeMode.none:
        break;

      case SoundscapeMode.solfeggio:
        // Deep Stillness: Lush meditative harmonic chord drone (C-G-C-E-G) with gentle choral beating
        final freqs = [130.81, 131.11, 196.00, 196.35, 261.63, 329.63, 392.00, 523.25];
        final weights = [0.26, 0.18, 0.22, 0.16, 0.20, 0.14, 0.12, 0.08];

        for (var i = 0; i < totalSamples; i++) {
          final t = i / sampleRate;
          // 0.125 Hz slow undulating breath cycle (8s period aligns with buffer)
          final breath = 0.78 + 0.22 * math.sin(2 * math.pi * 0.125 * t);
          var s = 0.0;
          for (var f = 0; f < freqs.length; f++) {
            s += weights[f] * math.sin(2 * math.pi * freqs[f] * t);
          }
          samples[i] = s * breath * 0.75;
        }
        break;

      case SoundscapeMode.rain:
        // Rainfall: Filtered pink noise + organic raindrop taps
        var pink = 0.0;
        var b0 = 0.0, b1 = 0.0;
        for (var i = 0; i < totalSamples; i++) {
          final white = rng.nextDouble() * 2.0 - 1.0;
          // Pink noise filter approximation
          b0 = 0.99765 * b0 + white * 0.0990460;
          b1 = 0.96300 * b1 + white * 0.2965164;
          pink = b0 + b1 + white * 0.1848;

          // Soft lowpass filter for gentle rain sound
          var out = pink * 0.18;

          // Random raindrop impacts (sine pop with fast decay)
          if (rng.nextDouble() < 0.0018) {
            final dropFreq = 750.0 + rng.nextDouble() * 900.0;
            final dropAmp = 0.22 + rng.nextDouble() * 0.28;
            final dropLen = math.min(totalSamples - i, (sampleRate * 0.015).toInt());
            for (var d = 0; d < dropLen; d++) {
              final dt = d / sampleRate;
              final env = math.exp(-dt * 260.0);
              samples[i + d] += dropAmp * env * math.sin(2 * math.pi * dropFreq * dt);
            }
          }
          samples[i] += out;
        }
        break;

      case SoundscapeMode.hearth:
        // Campfire: Warm brown noise rumble + realistic wood crackles and pops
        var brown = 0.0;
        for (var i = 0; i < totalSamples; i++) {
          final white = rng.nextDouble() * 2.0 - 1.0;
          brown = (brown + 0.035 * white) / 1.035;
          samples[i] += brown * 0.38;

          // Random micro fire crackles
          if (rng.nextDouble() < 0.0009) {
            final popAmp = 0.35 + rng.nextDouble() * 0.45;
            final popLen = math.min(totalSamples - i, (sampleRate * 0.010).toInt());
            for (var p = 0; p < popLen; p++) {
              final pt = p / sampleRate;
              final env = math.exp(-pt * 380.0);
              samples[i + p] += (rng.nextDouble() * 2.0 - 1.0) * popAmp * env;
            }
          }
        }
        break;

      case SoundscapeMode.wind:
        // Forest Wind: Sweeping resonant lowpass filter with slow undulating swells
        var low = 0.0;
        for (var i = 0; i < totalSamples; i++) {
          final t = i / sampleRate;
          final white = rng.nextDouble() * 2.0 - 1.0;

          // Modulating cutoff frequency between 220Hz and 600Hz
          final swell = 0.5 + 0.5 * math.sin(2 * math.pi * 0.125 * t);
          final cutoffCoeff = 0.05 + 0.08 * swell;

          low += cutoffCoeff * (white - low);
          samples[i] = low * (0.42 + 0.28 * swell);
        }
        break;
    }

    // Apply seamless cosine crossfade across loop boundary (last 0.35s blended with first 0.35s)
    final fadeCount = (sampleRate * 0.35).toInt();
    for (var i = 0; i < fadeCount; i++) {
      final prog = i / fadeCount;
      final w = 0.5 * (1.0 - math.cos(prog * math.pi));
      final startVal = samples[i];
      final endVal = samples[totalSamples - fadeCount + i];
      final blended = (1.0 - w) * endVal + w * startVal;
      samples[i] = blended;
      samples[totalSamples - fadeCount + i] = blended;
    }

    return _buildWavContainer(samples, sampleRate);
  }

  /// Builds a canonical 44-byte RIFF/WAVE container for 16-bit PCM audio.
  static Uint8List _buildWavContainer(List<double> samples, int sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final dataSize = samples.length * (bitsPerSample ~/ 8);
    final fileSize = 36 + dataSize;
    final byteData = ByteData(44 + dataSize);

    // RIFF chunk
    byteData.setUint8(0, 0x52); // R
    byteData.setUint8(1, 0x49); // I
    byteData.setUint8(2, 0x46); // F
    byteData.setUint8(3, 0x46); // F
    byteData.setUint32(4, fileSize, Endian.little);
    byteData.setUint8(8, 0x57);  // W
    byteData.setUint8(9, 0x41);  // A
    byteData.setUint8(10, 0x56); // V
    byteData.setUint8(11, 0x45); // E

    // "fmt " sub-chunk
    byteData.setUint8(12, 0x66); // f
    byteData.setUint8(13, 0x6D); // m
    byteData.setUint8(14, 0x74); // t
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // PCM sub-chunk size
    byteData.setUint16(20, 1, Endian.little);  // Format: 1 (PCM)
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * numChannels * 2, Endian.little); // Byte rate
    byteData.setUint16(32, numChannels * 2, Endian.little);              // Block align
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // "data" sub-chunk
    byteData.setUint8(36, 0x64); // d
    byteData.setUint8(37, 0x61); // a
    byteData.setUint8(38, 0x74); // t
    byteData.setUint8(39, 0x61); // a
    byteData.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i].clamp(-1.0, 1.0);
      final pcm = (s * 32767.0).toInt().clamp(-32768, 32767);
      byteData.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }
}
