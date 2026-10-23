import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/emotion_result.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/contracts/provider_contracts.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';
import 'package:solace_mobile/services/pending_recordings.dart';

class _NoAnalyzer implements EmotionAnalyzer {
  @override
  Future<List<EmotionResult>> analyze(SessionInput input) async => const [];
}

Uint8List _pcm() => Uint8List(32000);

void main() {
  late Directory dir;
  late PendingRecordings store;
  late InMemorySessionRepository repo;
  late SessionController sessions;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pending_rec_');
    store = PendingRecordings(directory: () async => dir);
    repo = InMemorySessionRepository();
    sessions = SessionController(repository: repo, emotionAnalyzer: _NoAnalyzer(), pendingRecordings: store);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('a recording made while the server is away', () {
    test('is kept on the phone and saved as a waiting entry that survives a restart', () async {
      final entry = await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm());
      expect(entry, isNotNull);
      expect(entry!.awaitingRecording, isTrue);
      expect(entry.text, isNull);
      expect(await store.read(entry.id), hasLength(32000));
      expect(sessions.awaitingRecordings, hasLength(1));
      expect(sessions.unread, isEmpty); // not "unread text": it has no words yet

      final restarted = SessionController(repository: repo, emotionAnalyzer: _NoAnalyzer(), pendingRecordings: store);
      await restarted.load();
      expect(restarted.awaitingRecordings.single.id, entry.id);
    });

    test('is written down when the server answers, and the recording is deleted afterwards', () async {
      final entry = (await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm()))!;
      final safety = <String>[];
      final done = await sessions.processPending(
        analyze: (id, pcm, words, face) async => const JournalAnalysis(transcript: 'I had a quiet day.', safety: 'support_suggested'),
        onSafety: (s, level) => safety.add(level),
      );
      expect(done, 1);
      final now = sessions.sessions.single;
      expect(now.id, entry.id);
      expect(now.awaitingRecording, isFalse);
      expect(now.text, 'I had a quiet day.');
      expect(await store.read(entry.id), isNull);
      expect(safety, ['support_suggested']); // a flagged delayed entry still reaches the safety flow
    });

    test("words the phone wrote are kept: they are sent to the server, and the server's own transcript never replaces them", () async {
      final entry = (await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm(), text: 'Phone words. With punctuation.'))!;
      String? sent;
      await sessions.processPending(analyze: (id, pcm, words, face) async {
        sent = words;
        return const JournalAnalysis(transcript: 'server words without punctuation');
      });
      expect(sent, 'Phone words. With punctuation.');
      final now = sessions.sessions.single;
      expect(now.id, entry.id);
      expect(now.text, 'Phone words. With punctuation.');
      expect(now.awaitingRecording, isFalse);
    });

    test("an entry the phone could not write down gets the server's words", () async {
      await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm());
      String? sent = 'unset';
      await sessions.processPending(analyze: (id, pcm, words, face) async {
        sent = words;
        return const JournalAnalysis(transcript: 'the server wrote this');
      });
      expect(sent, isNull);
      expect(sessions.sessions.single.text, 'the server wrote this');
    });

    test('stays waiting, with its audio, while the server is still away, and stops at the first failure', () async {
      final a = (await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm()))!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = (await sessions.savePendingRecording(mode: CaptureMode.video, pcm: _pcm()))!;
      var calls = 0;
      final done = await sessions.processPending(analyze: (id, pcm, words, face) async {
        calls++;
        return null;
      });
      expect(done, 0);
      expect(calls, 1); // did not hammer a server that is down
      expect(sessions.awaitingRecordings.map((s) => s.id), containsAll([a.id, b.id]));
      expect(await store.read(a.id), isNotNull);
    });

    test('goes oldest first', () async {
      final a = (await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm()))!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm());
      final order = <String>[];
      await sessions.processPending(analyze: (id, pcm, words, face) async {
        order.add(id);
        return const JournalAnalysis(transcript: 'words');
      });
      expect(order.first, a.id);
      expect(order, hasLength(2));
    });

    test('deleting the entry deletes the recording too', () async {
      final entry = (await sessions.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm()))!;
      await sessions.deleteSession(entry.id);
      expect(await store.read(entry.id), isNull);
      expect(sessions.sessions, isEmpty);
    });

    test('an old entry without the waiting fields still loads', () {
      final old = SessionRecord.fromMap({'id': '1', 'createdAt': '2026-01-01T00:00:00.000', 'mode': 'text', 'text': 'hi'});
      expect(old.awaitingRecording, isFalse);
      expect(SessionRecord.fromMap(old.toMap().cast<String, dynamic>()).awaitingRecording, isFalse);
    });

    test('nothing is saved when the phone cannot keep the recording', () async {
      final broken = PendingRecordings(directory: () async => throw const FileSystemException('full'));
      final c = SessionController(repository: repo, emotionAnalyzer: _NoAnalyzer(), pendingRecordings: broken);
      expect(await c.savePendingRecording(mode: CaptureMode.voice, pcm: _pcm()), isNull);
      expect(c.sessions, isEmpty);
    });
  });
}
