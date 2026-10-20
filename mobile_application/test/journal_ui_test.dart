import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/checkin/text_check_in_page.dart';
import 'package:solace_mobile/features/journal/journal_ui.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';

void main() {
  group('encouragement while recording', () {
    test('is warm, changes as the recording goes on, and never hurries the person', () {
      final lines = {
        for (final s in [3, 20, 60, 120, 170]) encouragement(seconds: s, faceTrouble: false),
      };
      expect(lines, hasLength(5));
      for (final line in lines) {
        for (final word in ['hurry', 'quick', 'faster', 'too long', 'must', 'should']) {
          expect(line.toLowerCase(), isNot(contains(word)));
        }
      }
    });

    test('says what is wrong with the picture when the face cannot be seen, and how to fix it', () {
      final line = encouragement(seconds: 30, faceTrouble: true);
      expect(line, contains('face'));
      expect(line, contains('closer'));
    });
  });

  group('sentence starters', () {
    test('lead with the part of the day, and are always a handful', () {
      expect(sentenceStarters(8).first, 'Today I hope…');
      expect(sentenceStarters(14).first, 'So far today…');
      expect(sentenceStarters(21).first, 'Today, I…');
      expect(sentenceStarters(8), hasLength(6));
    });
  });

  group('the text page', () {
    Future<void> open(WidgetTester tester, {Size size = const Size(1080, 2400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
      await tester.pumpWidget(
        MaterialApp(
          home: TextCheckInPage(
            sessionController: sessions,
            safetyController: SafetyController(screener: const KeywordSafetyScreener(), repository: InMemorySafetyEventRepository()),
          ),
        ),
      );
      await tester.pump();
    }

    String field(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('a sentence starter begins the entry', (tester) async {
      await open(tester);
      expect(field(tester), isEmpty);

      await tester.tap(find.byKey(const ValueKey('starter-Right now I feel…')));
      await tester.pump();

      expect(field(tester), 'Right now I feel… ');
    });

    testWidgets('a second starter continues the entry instead of replacing it', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const ValueKey('starter-Right now I feel…')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Right now I feel tired');
      await tester.pump();
      final second = find.byKey(const ValueKey('starter-Something that stayed with me…'));
      await tester.ensureVisible(second);
      await tester.pump();
      await tester.tap(second);
      await tester.pump();

      expect(field(tester), 'Right now I feel tired Something that stayed with me… ');
    });

    testWidgets('the line under the box changes as they write, and starts with no pressure', (tester) async {
      await open(tester);
      expect(find.text('No rush. A single word is enough.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tired');
      await tester.pumpAndSettle();
      expect(find.text('Good start. Keep going if you like.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tired but a bit lighter after a long walk by the river today, it helped more than I thought');
      await tester.pumpAndSettle();
      expect(find.text("That's it. Let it come."), findsOneWidget);
    });

    testWidgets('the box is on a short screen without scrolling', (tester) async {
      await open(tester, size: const Size(1080, 1800)); // 360 x 600

      expect(find.byType(TextField), findsOneWidget);
      expect(tester.getRect(find.byType(TextField)).bottom, lessThan(600));
    });

    testWidgets('fits when the text is enlarged', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
