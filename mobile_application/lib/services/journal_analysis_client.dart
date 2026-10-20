import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/companion_server_config.dart';
import '../core/models/emotion_result.dart';

/// What the companion server made of one journal entry: the words (typed, or
/// transcribed from a recording) and, when its emotion model is available, a
/// reading of how the entry sounded. [toResults] is empty when there is no
/// reading: an entry is then saved without an analysis, never with an invented one.
class JournalAnalysis {
  const JournalAnalysis({
    required this.transcript,
    this.safety,
    this.confidence,
    this.durationSeconds,
    this.emotion,
  });

  final String transcript;

  /// 'urgent_support', 'support_suggested' or null: the server's crisis-language check on the words.
  final String? safety;
  final double? confidence;
  final double? durationSeconds;
  final Map<String, dynamic>? emotion;

  factory JournalAnalysis.fromJson(Map<String, dynamic> json) {
    return JournalAnalysis(
      transcript: (json['transcript'] as String? ?? '').trim(),
      safety: json['safety'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      durationSeconds: (json['duration_s'] as num?)?.toDouble(),
      emotion: json['emotion'] is Map ? Map<String, dynamic>.from(json['emotion'] as Map) : null,
    );
  }

  /// The model's reading as an [EmotionResult] (none when the model gave no reading).
  List<EmotionResult> toResults({required String sessionId, DateTime? at}) {
    final em = emotion;
    final estimate = em?['estimate'];
    if (em == null || estimate is! Map) return const [];
    final classes = _probs(estimate['l7']);
    if (classes == null) return const [];
    final valenceProbs = _probs(estimate['lv']);
    final pattern = em['pattern'] as String? ?? '';
    final face = em['face'];
    final top = classes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      EmotionResult(
        sessionId: sessionId,
        modality: pattern.contains('A')
            ? EmotionModality.voice
            : pattern.contains('V')
                ? EmotionModality.face
                : EmotionModality.text,
        timestamp: at ?? DateTime.now(),
        valence: (em['valence'] as num?)?.toDouble(),
        arousal: (em['arousal'] as num?)?.toDouble(),
        labels: [for (final e in top.take(3)) EmotionLabel(label: e.key, score: e.value)],
        confidence: valenceProbs == null || valenceProbs.isEmpty
            ? null
            : valenceProbs.values.reduce((a, b) => a > b ? a : b),
        modelVersion: 'solace-${em['model_version'] ?? 'emotion'}-$pattern',
        classes: classes,
        valenceProbs: valenceProbs,
        arousalProbs: _probs(estimate['la']),
        mood: em['mood'] as String?,
        tier: em['tier'] as String?,
        pattern: pattern.isEmpty ? null : pattern,
        faceClasses: face is Map ? _probs(face['l7']) : null,
      ),
    ];
  }

  static Map<String, double>? _probs(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, double>{};
    raw.forEach((key, value) {
      if (key is String && value is num) out[key] = value.toDouble();
    });
    return out.isEmpty ? null : out;
  }
}

/// One HTTP exchange; replaceable so tests need no network.
typedef JournalTransport = Future<({int status, String body})> Function({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required List<int> body,
  required Duration timeout,
});

/// Talks to the companion server's journal endpoints (`/v1/journal/*`). Every
/// method returns null on ANY problem (server unreachable, slow, refusing): the
/// caller then saves the entry without an analysis.
class JournalAnalysisClient {
  JournalAnalysisClient({
    JournalTransport? transport,
    Future<Uri?> Function()? baseUri,
  })  : _transport = transport ?? _httpTransport,
        _baseUri = baseUri ?? _discoverBase;

  final JournalTransport _transport;
  final Future<Uri?> Function() _baseUri;

  /// Text typed by the person: the words are analysed as they are.
  Future<JournalAnalysis?> analyzeText(String sessionId, String text) {
    return _send(
      '/v1/journal/text',
      const {},
      utf8.encode(jsonEncode({'session_id': sessionId, 'text': text})),
      contentType: 'application/json',
      timeout: const Duration(seconds: 25),
    );
  }

  /// A whole recording (16 kHz mono int16 PCM). [face] says the person also agreed to
  /// the camera being read, so the frames sent with [sendFrame] may be used.
  Future<JournalAnalysis?> analyzeAudio(
    String sessionId,
    Uint8List pcm, {
    bool face = false,
    int sampleRate = 16000,
  }) {
    return _send(
      '/v1/journal/audio',
      {'session_id': sessionId, 'sample_rate': '$sampleRate', 'face': face ? '1' : '0'},
      pcm,
      contentType: 'application/octet-stream',
      timeout: const Duration(seconds: 120),
    );
  }

  /// One upright JPEG taken while recording a video journal. True/false: a usable face was
  /// (not) found; null: unknown or not accepted.
  Future<bool?> sendFrame(String sessionId, Uint8List jpeg) async {
    final base = await _baseUri();
    if (base == null) return null;
    try {
      final reply = await _transport(
        method: 'POST',
        uri: base.replace(path: '/v1/journal/frame', queryParameters: {'session_id': sessionId}),
        headers: const {'Content-Type': 'image/jpeg'},
        body: jpeg,
        timeout: const Duration(seconds: 4),
      );
      if (reply.status != 200) return null;
      final usable = (jsonDecode(reply.body) as Map<String, dynamic>)['usable'];
      return usable is num ? usable != 0 : null;
    } catch (_) {
      return null;
    }
  }

  Future<JournalAnalysis?> _send(
    String path,
    Map<String, String> query,
    List<int> body, {
    required String contentType,
    required Duration timeout,
  }) async {
    final base = await _baseUri();
    if (base == null) return null;
    try {
      final reply = await _transport(
        method: 'POST',
        uri: base.replace(path: path, queryParameters: query.isEmpty ? null : query),
        headers: {'Content-Type': contentType},
        body: body,
        timeout: timeout,
      );
      if (reply.status != 200) return null;
      return JournalAnalysis.fromJson(jsonDecode(reply.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Journal] analysis unavailable: ${e.runtimeType}');
      return null;
    }
  }

  static Future<({int status, String body})> _httpTransport({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int> body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      headers.forEach(request.headers.set);
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      return (status: response.statusCode, body: text);
    } finally {
      client.close(force: true);
    }
  }

  static Uri? _cachedBase;
  static DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The first known companion address that answers `/healthz`: the saved one, then the usual candidates.
  static Future<Uri?> _discoverBase() async {
    if (_cachedBase != null && DateTime.now().difference(_cachedAt) < const Duration(minutes: 2)) {
      return _cachedBase;
    }
    var port = CompanionServerConfig.defaultPort;
    var saved = <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      port = prefs.getInt(CompanionServerConfig.prefKeyPort) ?? port;
      final host = prefs.getString(CompanionServerConfig.prefKeyHost);
      if (host != null && host.isNotEmpty) saved = [host];
    } catch (_) {}
    final hosts = <String>{...saved, ...CompanionServerConfig.candidateHosts};
    for (final host in hosts) {
      final uri = Uri(scheme: 'http', host: host, port: port);
      try {
        final reply = await _httpTransport(
          method: 'GET',
          uri: uri.replace(path: '/healthz'),
          headers: const {},
          body: const [],
          timeout: const Duration(milliseconds: 1500),
        );
        if (reply.status == 200) {
          _cachedBase = uri;
          _cachedAt = DateTime.now();
          return uri;
        }
      } catch (_) {}
    }
    return null;
  }
}
