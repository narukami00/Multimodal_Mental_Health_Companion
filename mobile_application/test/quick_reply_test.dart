import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/safety_assessment.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/domain/rhythm/quick_reply.dart';
import 'package:solace_mobile/features/checkin/quick_reply_importer.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/quick_reply_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuickReply', () {
    test('survives being written down and read back', () {
      final reply = QuickReply(text: 'calm, mostly', at: DateTime(2026, 11, 7, 21, 5));
      final back = QuickReply.decode(reply.encode())!;
      expect(back.text, 'calm, mostly');
      expect(back.at, DateTime(2026, 11, 7, 21, 5));
    });

    test('anything that is not a usable reply is dropped, not thrown', () {
      expect(QuickReply.decode('not json'), isNull);
      expect(QuickReply.decode('[]'), isNull);
      expect(QuickReply.decode('{"text":"   ","at":"2026-11-07T10:00:00"}'), isNull);
      expect(QuickReply.decode('{"text":"ok","at":"yesterday"}'), isNull);
    });

    test('is tidied and kept short', () {
      expect(cleanQuickReply('  fine   today \n\n\n\n thanks '), 'fine today \n\n thanks');
      expect(cleanQuickReply('   '), isNull);
      expect(cleanQuickReply(null), isNull);
      expect(cleanQuickReply('a' * 5000)!.length, quickReplyMaxLength);
    });
  });

  group('QuickReplyInbox', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('holds replies and hands them over once, oldest first', () async {
      final prefs = await SharedPreferences.getInstance();
      await QuickReplyInbox.add(prefs, QuickReply(text: 'later', at: DateTime(2026, 11, 7, 22)));
      await QuickReplyInbox.add(prefs, QuickReply(text: 'earlier', at: DateTime(2026, 11, 7, 9)));

      final first = await QuickReplyInbox.drain(prefs);
      expect(first.map((r) => r.text), ['earlier', 'later']);
      expect(await QuickReplyInbox.drain(prefs), isEmpty);
    });

    test('a damaged entry does not hide the good ones', () async {
      SharedPreferences.setMockInitialValues({
        QuickReplyInbox.preferenceKey: [
          'garbage',
          QuickReply(text: 'fine', at: DateTime(2026, 11, 7, 8)).encode(),
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      final drained = await QuickReplyInbox.drain(prefs);
      expect(drained.single.text, 'fine');
    });

    test('the notification handler holds the words, and ignores other actions and empty boxes', () async {
      NotificationResponse response(String? action, String? input) => NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: action,
        input: input,
      );

      await quickReplyBackground(response('something_else', 'hello'));
      await quickReplyBackground(response(quickReplyActionId, '   '));
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(QuickReplyInbox.preferenceKey), isNull);

      await quickReplyBackground(response(quickReplyActionId, ' tired '));
      prefs = await SharedPreferences.getInstance();
      final held = prefs.getStringList(QuickReplyInbox.preferenceKey)!;
      expect(held, hasLength(1));
      expect(QuickReply.decode(held.single)!.text, 'tired');
    });
  });

  group('QuickReplyImporter', () {
    late SessionController sessions;
    late SafetyController safety;
    late List<SafetyAssessment> shown;

    QuickReplyImporter importer(List<QuickReply> replies) {
      var given = false;
      return QuickReplyImporter(
        drain: () async {
          if (given) return const [];
          given = true;
          return replies;
        },
        safety: safety,
        sessions: sessions,
        showSupport: (assessment) async => shown.add(assessment),
      );
    }

    setUp(() {
      sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
      safety = SafetyController(screener: const KeywordSafetyScreener(), repository: InMemorySafetyEventRepository());
      shown = [];
    });

    test('saves each reply as a text check-in dated when it was written', () async {
      final saved = await importer([
        QuickReply(text: 'okay', at: DateTime(2026, 11, 6, 21, 30)),
        QuickReply(text: 'better', at: DateTime(2026, 11, 7, 8, 15)),
      ]).run();

      expect(saved, 2);
      expect(sessions.sessions, hasLength(2));
      final byText = {for (final s in sessions.sessions) s.text: s};
      expect(byText['okay']!.createdAt, DateTime(2026, 11, 6, 21, 30));
      expect(byText['okay']!.mode, CaptureMode.text);
      expect(byText['better']!.createdAt, DateTime(2026, 11, 7, 8, 15));
      expect(shown, isEmpty);
    });

    test('nothing waiting means nothing saved', () async {
      expect(await importer(const []).run(), 0);
      expect(sessions.sessions, isEmpty);
    });

    test('words that call for support are still kept, and support is offered once, after', () async {
      final saved = await importer([
        QuickReply(text: 'fine', at: DateTime(2026, 11, 7, 7)),
        QuickReply(text: 'I want to end my life', at: DateTime(2026, 11, 7, 8)),
        QuickReply(text: 'so tired of everything, suicide', at: DateTime(2026, 11, 7, 9)),
      ]).run();

      expect(saved, 3, reason: 'the person already wrote them, so they are kept');
      expect(shown, hasLength(1));
      expect(shown.single.level, isNot(SafetyLevel.clear));
    });
  });
}
