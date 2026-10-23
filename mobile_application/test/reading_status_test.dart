import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/journal/reading_status.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';

/// A client whose server answers /healthz with [health] (or is away when [away]).
JournalAnalysisClient _client({Map<String, dynamic>? health, bool away = false, int status = 200}) => JournalAnalysisClient(
      baseUri: () async => away ? null : Uri.parse('http://x:8000'),
      transport: ({required method, required uri, required headers, required body, required timeout}) async {
        expect(uri.path, '/healthz');
        return (status: status, body: jsonEncode(health ?? {'status': 'ok'}));
      },
    );

void main() {
  group('asking the server whether emotion reading works', () {
    test('reads the server\'s own report', () async {
      expect(await _client(health: {'emotion': {'state': 'ready', 'face': true}}).emotionState(), 'ready');
      expect(await _client(health: {'emotion': {'state': 'off', 'face': false}}).emotionState(), 'off');
      expect(await _client(health: {'emotion': {'state': 'unavailable', 'face': false}}).emotionState(), 'unavailable');
    });

    test('an older server that does not say is "unknown", never a false alarm', () async {
      expect(await _client(health: {'status': 'ok'}).emotionState(), 'unknown');
    });

    test('no server, or a server that errors, is null', () async {
      expect(await _client(away: true).emotionState(), isNull);
      expect(await _client(status: 503).emotionState(), isNull);
    });
  });

  group('why there is no reading', () {
    test('without the person\'s OK, that is the reason, and the server is not even asked', () async {
      var asked = 0;
      final client = JournalAnalysisClient(
        baseUri: () async {
          asked++;
          return Uri.parse('http://x:8000');
        },
        transport: ({required method, required uri, required headers, required body, required timeout}) async => (status: 200, body: '{}'),
      );
      expect(await readingStatus(client: client, consentGranted: false), ReadingStatus.needsConsent);
      expect(asked, 0);
    });

    test('each situation is told apart', () async {
      expect(await readingStatus(client: _client(away: true), consentGranted: true), ReadingStatus.serverAway);
      expect(await readingStatus(client: _client(health: {'emotion': {'state': 'off'}}), consentGranted: true), ReadingStatus.emotionOff);
      expect(await readingStatus(client: _client(health: {'emotion': {'state': 'unavailable'}}), consentGranted: true), ReadingStatus.emotionNotAnswering);
      expect(await readingStatus(client: _client(health: {'emotion': {'state': 'ready'}}), consentGranted: true), ReadingStatus.ready);
      expect(await readingStatus(client: _client(health: {'status': 'ok'}), consentGranted: true), ReadingStatus.ready);
    });

    test('every situation has its own calm sentence, and none is the old guess', () {
      final sentences = {for (final s in ReadingStatus.values) s: explainReadingStatus(s)};
      expect(sentences.values.toSet().length, ReadingStatus.values.length); // all different
      for (final text in sentences.values) {
        expect(text, isNot(contains("or reading isn't switched on")));
        expect(text.toLowerCase(), isNot(contains('exception')));
        expect(text.toLowerCase(), isNot(contains('error')));
      }
      expect(sentences[ReadingStatus.serverAway], contains("isn't reachable"));
      expect(sentences[ReadingStatus.emotionOff], contains('switched off'));
      expect(sentences[ReadingStatus.emotionNotAnswering], contains('may still be starting'));
      expect(sentences[ReadingStatus.needsConsent], contains('OK'));
    });

    test('explainNoReading gives the sentence for what it found', () async {
      expect(await explainNoReading(client: _client(health: {'emotion': {'state': 'off'}}), consentGranted: true), contains('switched off'));
      expect(await explainNoReading(client: _client(away: true), consentGranted: true), contains("isn't reachable"));
    });
  });
}
