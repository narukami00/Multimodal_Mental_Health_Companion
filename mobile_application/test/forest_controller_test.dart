import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/session_input.dart';
import 'package:solace_mobile/core/models/session_record.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';
import 'package:solace_mobile/features/forest/forest_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';

void main() {
  late SessionController sessions;
  late InMemoryForestStore store;
  // Entries are stamped with the real time, so the tests' clock starts from it too.
  var now = DateTime.now();

  setUp(() {
    now = DateTime.now();
    sessions = SessionController(repository: InMemorySessionRepository(), emotionAnalyzer: const MockEmotionAnalyzer());
    store = InMemoryForestStore();
  });

  Future<ForestController> start() async {
    final c = ForestController(store: store, sessions: sessions, clock: () => now);
    await c.load();
    return c;
  }

  test('history is replayed: past days fill the tree quietly, and entries made today wait to be poured', () async {
    final repository = InMemorySessionRepository();
    final base = DateTime.now();
    for (var d = 1; d <= 9; d++) {
      // one check-in a day for nine earlier days
      await repository.save(SessionRecord(
        id: 'old$d',
        createdAt: DateTime(base.year, base.month, base.day - d, 9),
        mode: CaptureMode.text,
        mood: 'Steady',
      ));
    }
    sessions = SessionController(repository: repository, emotionAnalyzer: const MockEmotionAnalyzer());
    await sessions.load();
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Bright'); // today
    final forest = await start();
    expect(forest.waiting, hasLength(1)); // only today's is poured
    expect(forest.garden.finished, hasLength(1)); // nine waters: one tree, two on the next
    expect(forest.garden.currentProgress, 2);
    expect(forest.garden.finished.single.waters, isNotEmpty); // and it remembers what grew it
  });

  test('starting with nothing gives a seed', () async {
    final forest = await start();
    expect(forest.waiting, isEmpty);
    expect(forest.garden.currentProgress, 0);
    expect(forest.waterWaiting, isFalse);
  });

  test('a new entry waters the tree, waits to be poured, and is poured once', () async {
    final forest = await start();
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    expect(forest.waterWaiting, isTrue);
    expect(forest.waiting, hasLength(1));
    expect(forest.garden.currentProgress, 0); // nothing shown until it is watched
    expect(forest.gardenAfter(1).currentProgress, 1);

    await forest.markWatched();
    expect(forest.waterWaiting, isFalse);
    expect(forest.garden.currentProgress, 1);
    await forest.markWatched();
    expect(forest.garden.currentProgress, 1); // no double counting
  });

  test('voice and video entries are journals, worth more', () async {
    final forest = await start();
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    await forest.markWatched();
    now = DateTime.now().add(const Duration(days: 1));
    await sessions.saveSession(mode: CaptureMode.voice, text: 'hello');
    expect(forest.gardenAfter(1).currentProgress, 3); // 1 from yesterday + 2 for the first journal today
  });

  test('yesterday\'s waters are already in the tree when the next day starts', () async {
    final forest = await start();
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    now = DateTime.now().add(const Duration(days: 1));
    expect(forest.waiting, isEmpty);
    expect(forest.garden.currentProgress, 1);
  });

  test('it remembers across restarts, and does not count the same entry twice', () async {
    var forest = await start();
    await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    await forest.markWatched();
    forest.dispose();

    forest = await start();
    expect(forest.garden.currentProgress, 1);
    expect(forest.waiting, isEmpty);
    expect(forest.events, hasLength(1));
  });

  test('deleting an entry never makes the tree smaller', () async {
    final forest = await start();
    final entry = await sessions.saveSession(mode: CaptureMode.text, mood: 'Steady');
    await forest.markWatched();
    await sessions.deleteSession(entry.id);
    expect(forest.garden.currentProgress, 1);
  });
}
