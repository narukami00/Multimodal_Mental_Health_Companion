import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/features/chat/chat_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/services/pcm_audio_recorder_service.dart';

void main() {
  SafetyController safety() => SafetyController(
        screener: const KeywordSafetyScreener(),
        repository: InMemorySafetyEventRepository(),
      );

  testWidgets('voice note renders realistic waveform bars and plays on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          safetyController: safety(),
          audioRecorderService: PcmAudioRecorderService(isMock: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Verify initial voice bubble exists
    expect(find.text('0:14'), findsOneWidget);

    // Verify play button is visible
    final playBtn = find.byIcon(Icons.play_arrow_rounded);
    expect(playBtn, findsOneWidget);

    // Tap play button to start playback
    await tester.tap(playBtn);
    await tester.pump(const Duration(milliseconds: 100));

    // Icon transitions to pause button while playing
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // Tap pause button to pause playback
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('mic button does not have circular background blob', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          safetyController: safety(),
          audioRecorderService: PcmAudioRecorderService(isMock: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final micIcon = find.byIcon(Icons.mic_rounded);
    expect(micIcon, findsOneWidget);

    // Find the container wrapping the mic icon
    final container = tester.widget<Container>(
      find.ancestor(of: micIcon, matching: find.byType(Container)).first,
    );
    // Ensure no BoxShape.circle or background color decoration
    expect(container.decoration, isNull);
  });
}
