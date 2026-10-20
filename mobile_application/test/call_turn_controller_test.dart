import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/features/call/call_turn_controller.dart';

CallTurnController controller() => CallTurnController(clock: Stopwatch());

void main() {
  group('turn table (spec §7.4)', () {
    test('idle -> turnStarted -> userSpeaking', () {
      final c = controller();
      expect(c.currentPhase, CallPhase.idle);
      c.onTurnStarted('turn_1');
      expect(c.currentPhase, CallPhase.userSpeaking);
      expect(c.activeTurnId, 'turn_1');
      c.dispose();
    });

    test('userSpeaking -> speechDetected stays userSpeaking', () {
      final c = controller();
      c.onTurnStarted('turn_1');
      c.onSpeechDetected('turn_1', offsetMs: 140, confidence: 0.81);
      expect(c.currentPhase, CallPhase.userSpeaking);
      c.dispose();
    });

    test('userSpeaking -> endpointed -> thinking, and sub-stages do not move it',
        () {
      final c = controller();
      c.onTurnStarted('turn_1');
      c.onEndpointed('turn_1', speechMs: 620, silenceMs: 700);
      expect(c.currentPhase, CallPhase.thinking);

      c.onProcessing('turn_1', TurnStage.stt, elapsedMs: 210);
      expect(c.currentPhase, CallPhase.thinking);
      expect(c.stage, TurnStage.stt);
      c.onProcessing('turn_1', TurnStage.llmTimeout, elapsedMs: 4000);
      expect(c.currentPhase, CallPhase.thinking);
      c.dispose();
    });

    test('thinking -> firstAudioFrame -> assistantSpeaking -> ttsComplete -> idle',
        () {
      final c = controller();
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.llmFirstToken);
      expect(c.currentPhase, CallPhase.thinking);
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      expect(c.currentPhase, CallPhase.assistantSpeaking);
      c.onTtsComplete();
      expect(c.currentPhase, CallPhase.idle);
      c.dispose();
    });

    test('assistantSpeaking -> interrupted -> userSpeaking (the barge-in)', () {
      final c = controller();
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      c.onInterrupted(turnId: 't2', playedMs: 1840);
      expect(c.currentPhase, CallPhase.userSpeaking);
      c.dispose();
    });

    test('thinking -> discarded -> idle, and a stale turn id is ignored', () {
      final c = controller();
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onDiscarded('other', DiscardReason.silence);
      expect(c.currentPhase, CallPhase.thinking);
      c.onDiscarded('t', DiscardReason.echo);
      expect(c.currentPhase, CallPhase.idle);
      c.dispose();
    });

    test('cancelled returns to idle from any turn state', () {
      final c = controller();
      c.onTurnStarted('t');
      c.onTurnCancelled();
      expect(c.currentPhase, CallPhase.idle);
      c.dispose();
    });

    test('callEnded is terminal and ignores further events', () {
      final c = controller();
      c.onTurnStarted('t');
      c.onCallEnded();
      expect(c.currentPhase, CallPhase.ended);
      c.onTurnStarted('late');
      c.onServerIdle();
      expect(c.currentPhase, CallPhase.ended);
      c.dispose();
    });

    test('an illegal pair is absorbed, not fatal (a race, not a state)',
        () async {
      final c = controller();
      final seen = <CallPhaseTransition>[];
      c.transitions.listen(seen.add);
      // endpointed from idle has no row in the §7.4 table.
      c.onEndpointed('nope');
      await Future<void>.delayed(Duration.zero);
      expect(c.currentPhase, CallPhase.idle);
      expect(seen, isEmpty);
      c.dispose();
    });

    test('assistantSpeaking -> turnStarted takes the floor (server race)', () {
      final c = controller();
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      expect(c.currentPhase, CallPhase.assistantSpeaking);
      c.onTurnStarted('t2');
      expect(c.currentPhase, CallPhase.userSpeaking);
      c.dispose();
    });

    test('every transition is logged with its cause', () async {
      final c = controller();
      final seen = <CallPhaseTransition>[];
      c.transitions.listen(seen.add);
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((t) => '${t.from.name}->${t.to.name}'), [
        'idle->userSpeaking',
        'userSpeaking->thinking',
        'thinking->assistantSpeaking',
      ]);
      expect(seen.every((t) => t.tMs >= 0), isTrue);
      c.dispose();
    });
  });

  group('the server reports where the call stands', () {
    test('server idle ends whatever the phone still showed as in flight', () {
      for (final setUp in <void Function(CallTurnController)>[
        (c) => c.onTurnStarted('t'),
        (c) {
          c.onTurnStarted('t');
          c.onEndpointed('t');
        },
        (c) {
          c.onTurnStarted('t');
          c.onEndpointed('t');
          c.onProcessing('t', TurnStage.ttsFirstFrame);
        },
      ]) {
        final c = controller();
        setUp(c);
        expect(c.currentPhase, isNot(CallPhase.idle));
        c.onServerIdle();
        expect(c.currentPhase, CallPhase.idle);
        c.dispose();
      }
    });

    test('server idle while already idle is a no-op, not an illegal pair', () async {
      final c = controller();
      final seen = <CallPhaseTransition>[];
      c.transitions.listen(seen.add);
      c.onServerIdle();
      await Future<void>.delayed(Duration.zero);
      expect(c.currentPhase, CallPhase.idle);
      c.dispose();
    });

    test('speaking over Sol takes the floor; a false alarm hands it back', () {
      final c = controller();
      c.onTurnStarted('t');
      c.onEndpointed('t');
      c.onProcessing('t', TurnStage.ttsFirstFrame);
      c.onInterrupted(turnId: null, playedMs: 900);
      expect(c.currentPhase, CallPhase.userSpeaking);
      c.onTtsResume('utt_1', 900);
      expect(c.currentPhase, CallPhase.assistantSpeaking);
      c.dispose();
    });
  });

  group('mute and unmute (spec §8.2 composite state)', () {
    test('mute is a modulation over the active state and unmute restores it',
        () {
      final c = controller();
      c.onTurnStarted('t');
      expect(c.currentPhase, CallPhase.userSpeaking);
      c.onMicMutedChanged(true);
      expect(c.currentPhase, CallPhase.muted);
      c.onMicMutedChanged(false);
      expect(c.currentPhase, CallPhase.userSpeaking);
      c.dispose();
    });
  });
}
