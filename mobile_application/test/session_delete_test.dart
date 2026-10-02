import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/data/repositories/shared_preferences_session_repository.dart';
import 'package:solace_mobile/features/journal/session_detail_page.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

SessionRecord _session(String id, {String text = 'A good walk by the river.'}) => SessionRecord(
  id: id,
  createdAt: DateTime(2026, 10, 20, 9),
  mode: CaptureMode.text,
  text: text,
  mood: 'Steady',
);

void main() {
  group('repositories', () {
    test('in memory: deletes one entry and tolerates a missing one', () async {
      final repository = InMemorySessionRepository();
      await repository.save(_session('a'));
      await repository.save(_session('b'));

      await repository.delete('a');
      await repository.delete('nope');

      expect((await repository.listSessions()).map((s) => s.id), ['b']);
    });

    test('shared preferences: the deletion survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = SharedPreferencesSessionRepository(prefs);
      await repository.save(_session('a'));
      await repository.save(_session('b'));

      await repository.delete('a');

      final reopened = SharedPreferencesSessionRepository(prefs);
      expect((await reopened.listSessions()).map((s) => s.id), ['b']);
      expect(await reopened.findById('a'), isNull);
    });
  });

  group('controller', () {
    late InMemorySessionRepository repository;
    late SessionController controller;

    setUp(() async {
      repository = InMemorySessionRepository();
      await repository.save(_session('a'));
      await repository.save(_session('b'));
      controller = SessionController(
        repository: repository,
        emotionAnalyzer: const MockEmotionAnalyzer(),
      );
      await controller.load();
    });

    test('deleting removes the entry, tells listeners, and reports what went', () async {
      var notified = 0;
      controller.addListener(() => notified++);
      SessionRecord? gone;
      controller.onDeleted = (s) => gone = s;

      await controller.deleteSession('a');

      expect(controller.sessions.map((s) => s.id), ['b']);
      expect(notified, 1);
      expect(gone?.id, 'a');
      expect(await repository.findById('a'), isNull);
    });

    test('deleting an entry that is not there does nothing', () async {
      var called = false;
      controller.onDeleted = (_) => called = true;

      await controller.deleteSession('nope');

      expect(called, isFalse);
      expect(controller.sessions, hasLength(2));
    });
  });

  group('the entry page', () {
    Future<void> open(WidgetTester tester, {Future<void> Function(SessionRecord)? onDelete}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionDetailPage(session: _session('a'), onDelete: onDelete),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers no delete when nothing can delete it', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('delete-entry')), findsNothing);
    });

    testWidgets('asks first, and keeping it changes nothing', (tester) async {
      SessionRecord? deleted;
      await open(tester, onDelete: (s) async => deleted = s);

      await tester.ensureVisible(find.byKey(const ValueKey('delete-entry')));
      await tester.tap(find.byKey(const ValueKey('delete-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(deleted, isNull);
      expect(find.byType(SessionDetailPage), findsOneWidget);
    });

    testWidgets('confirming deletes it and closes the page', (tester) async {
      SessionRecord? deleted;
      await open(tester, onDelete: (s) async => deleted = s);

      await tester.ensureVisible(find.byKey(const ValueKey('delete-entry')));
      await tester.tap(find.byKey(const ValueKey('delete-entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-entry-confirm')));
      await tester.pumpAndSettle();

      expect(deleted?.id, 'a');
      expect(find.byType(SessionDetailPage), findsNothing);
    });
  });
}
