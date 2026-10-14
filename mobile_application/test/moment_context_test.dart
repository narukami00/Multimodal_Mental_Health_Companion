import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/memory_moment.dart';
import 'package:solace_mobile/domain/memory/moment_extractor.dart';
import 'package:solace_mobile/domain/memory/server_moment_extractor.dart';

const _context = [
  MomentContextLine(fromPerson: true, text: 'I might start working again, maybe part time.'),
  MomentContextLine(fromPerson: false, text: 'Working could give you some structure. How does that sound?'),
];

MomentCandidate _reply(String text, {List<MomentContextLine> context = const []}) => MomentCandidate(
  text: text,
  source: MomentSource.chat,
  createdAt: DateTime(2026, 10, 20),
  sourceRef: 'chat:m9',
  context: context,
);

void main() {
  group('a reply that points back', () {
    test('is kept as what it was about, not as a bare fragment', () {
      expect(
        acceptQuotedMoment('That was a great idea.', 'About working: That was a great idea.', context: _context),
        'About working: That was a great idea.',
      );
    });

    test('a faithful copy of the bare fragment is refused: it would mean nothing later', () {
      expect(acceptQuotedMoment('That was a great idea.', 'That was a great idea.', context: _context), isNull);
      expect(acceptQuotedMoment('That was a great idea.', 'That was a great idea.'), isNull);
    });

    test('an invention is refused even when the earlier lines are available', () {
      expect(acceptQuotedMoment('That was a great idea.', 'About Paris: That was a great idea.', context: _context), isNull);
    });

    test('the line must come from what they said, not only from the earlier lines', () {
      expect(acceptQuotedMoment('Okay.', 'Working could give you some structure.', context: _context), isNull);
    });

    test('a hard topic in the earlier lines blocks it', () {
      final hard = [
        ..._context,
        const MomentContextLine(fromPerson: true, text: 'My grandmother died and working helps.'),
      ];
      expect(acceptQuotedMoment('That was a great idea.', 'About working: That was a great idea.', context: hard), isNull);
    });
  });

  group('vague lines', () {
    test('are recognised', () {
      expect(momentIsVague('That was a great idea.'), isTrue);
      expect(momentIsVague('It was so nice.'), isTrue);
      expect(momentIsVague('sounds great to me'), isTrue);
      expect(momentIsVague('Working is a great idea.'), isFalse);
      expect(momentIsVague('About working: That was a great idea.'), isFalse);
      expect(momentIsVague('I had coffee with a friend and it was really nice.'), isFalse);
    });

    test('are not proposed by the offline reader either', () async {
      const reader = RuleBasedMomentExtractor();
      expect(await reader.extract(_reply('I did it and it was really great.')), isNull);
      expect(await reader.extract(_reply('I had coffee with a friend and it was really nice.')), isNotNull);
    });
  });

  group('the server reader', () {
    test('sends the earlier lines with the message and keeps the resolved answer', () async {
      List<MomentContextLine>? sent;
      final extractor = ServerMomentExtractor(
        requesterProvider: () => (text, context) async {
          sent = context;
          return 'About working: That was a great idea.';
        },
      );
      final proposal = await extractor.extract(_reply('That was a great idea.', context: _context));
      expect(proposal?.text, 'About working: That was a great idea.');
      expect(sent, hasLength(2));
      expect(sent!.first.fromPerson, isTrue);
      expect(sent!.last.fromPerson, isFalse);
    });

    test('with no usable answer, a vague message yields no moment at all', () async {
      final extractor = ServerMomentExtractor(requesterProvider: () => (text, context) async => null);
      expect(await extractor.extract(_reply('That was a great idea.', context: _context)), isNull);
    });
  });
}
