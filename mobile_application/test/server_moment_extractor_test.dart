import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/domain/memory/moment_extractor.dart';
import 'package:solace_mobile/domain/memory/server_moment_extractor.dart';

const _original = 'Work was long. I had coffee with a friend and it was really nice. Tired now.';
const _quote = 'I had coffee with a friend and it was really nice.';

MomentCandidate _candidate(String text, {MomentSource source = MomentSource.chat}) =>
    MomentCandidate(
      text: text,
      source: source,
      createdAt: DateTime(2026, 10, 20),
      sourceRef: 'chat:m1',
    );

void main() {
  group('acceptQuotedMoment', () {
    test('accepts a faithful quote and tidies quotes and spaces', () {
      expect(acceptQuotedMoment(_original, _quote), _quote);
      expect(acceptQuotedMoment(_original, '  "$_quote"\n'), _quote);
    });

    test('rejects nothing, NONE, rewording, inventions, and sensitive topics', () {
      expect(acceptQuotedMoment(_original, null), isNull);
      expect(acceptQuotedMoment(_original, 'NONE'), isNull);
      expect(acceptQuotedMoment(_original, ''), isNull);
      expect(
        acceptQuotedMoment(_original, 'You had a wonderful afternoon at the beach with family.'),
        isNull,
      );
      expect(
        acceptQuotedMoment(
          'My grandmother died last week. $_quote',
          _quote,
        ),
        isNull,
      );
    });

    test('rejects what is too long or too short', () {
      final long = 'I had a nice time ${'and then we walked ' * 20}';
      expect(acceptQuotedMoment(long, long), isNull);
      expect(acceptQuotedMoment('Nice day out.', 'Nice day out.'), isNull);
    });
  });

  group('ServerMomentExtractor', () {
    test('uses the server for chat and carries the usual fields', () async {
      final extractor = ServerMomentExtractor(
        requesterProvider: () => (text) async => _quote,
      );
      final proposal = (await extractor.extract(_candidate(_original)))!;

      expect(proposal.text, _quote);
      expect(proposal.source, MomentSource.chat);
      expect(proposal.occurredOn, '2026-10-20');
      expect(proposal.sourceRef, 'chat:m1');
    });

    test('never sends a journal entry or a check-in to the server', () async {
      var asked = false;
      final extractor = ServerMomentExtractor(
        requesterProvider: () => (text) async {
          asked = true;
          return _quote;
        },
      );

      for (final source in [MomentSource.journal, MomentSource.checkIn]) {
        await extractor.extract(_candidate(_original, source: source));
      }
      expect(asked, isFalse);
    });

    test('falls back to the offline reader with no connection', () async {
      final extractor = ServerMomentExtractor(requesterProvider: () => null);
      final proposal = await extractor.extract(_candidate(_original));

      expect(proposal!.text, _quote);
    });

    test('falls back when the server has nothing, errors, is slow, or invents', () async {
      MomentRequester? reply;
      final extractor = ServerMomentExtractor(
        requesterProvider: () => reply,
        timeout: const Duration(milliseconds: 50),
      );

      for (final r in <MomentRequester>[
        (text) async => null,
        (text) async => throw StateError('socket closed'),
        (text) => Future.delayed(const Duration(seconds: 2), () => _quote),
        (text) async => 'A completely different sentence that was never said anywhere.',
      ]) {
        reply = r;
        final proposal = await extractor.extract(_candidate(_original));
        // The offline reader still finds the same sentence.
        expect(proposal?.text, _quote);
      }
    });

    test('a sensitive message yields nothing from either reader', () async {
      final extractor = ServerMomentExtractor(
        requesterProvider: () => (text) async => _quote,
      );
      final proposal = await extractor.extract(
        _candidate('My grandmother died last week. $_original'),
      );
      expect(proposal, isNull);
    });
  });
}
