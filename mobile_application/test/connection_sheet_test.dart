import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/constants/companion_server_config.dart';
import 'package:solace_mobile/features/chat/connection_sheet.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';

Widget _sheet({
  CompanionConnectionStatus status = CompanionConnectionStatus.disconnected,
  bool tts = true,
  void Function(String, int)? onConnect,
  ValueChanged<String>? onVoice,
  double keyboard = 0,
  Size size = const Size(360, 640),
  double textScale = 1,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        viewInsets: EdgeInsets.only(bottom: keyboard),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConnectionSheetView(
            initialHost: CompanionServerConfig.defaultTailscaleIp,
            initialPort: 8000,
            status: status,
            latencyMs: 6,
            ttsEnabled: tts,
            voiceId: 'af_heart',
            onConnect: onConnect ?? (_, __) {},
            onDisconnect: () {},
            onPing: () {},
            onTtsChanged: (_) {},
            onVoiceChanged: onVoice ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the state, the routes and the voice', (tester) async {
    await tester.pumpWidget(_sheet(status: CompanionConnectionStatus.connected));
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Live · 6 ms'), findsOneWidget);
    expect(find.text('Tailscale'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-disconnect')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-af_bella')), findsOneWidget);
  });

  testWidgets('a route fills the address, and connecting reports host and port', (tester) async {
    String? host;
    int? port;
    await tester.pumpWidget(_sheet(onConnect: (h, p) {
      host = h;
      port = p;
    }));
    await tester.tap(find.byKey(ValueKey('route-${CompanionServerConfig.defaultLanIp}')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('connection-host'))).controller!.text, CompanionServerConfig.defaultLanIp);
    await tester.tap(find.byKey(const ValueKey('connection-connect')));
    expect(host, CompanionServerConfig.defaultLanIp);
    expect(port, 8000);
  });

  testWidgets('a voice can be chosen only when speaking is on', (tester) async {
    String? chosen;
    await tester.pumpWidget(_sheet(onVoice: (v) => chosen = v));
    await tester.ensureVisible(find.byKey(const ValueKey('voice-am_michael')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-am_michael')));
    expect(chosen, 'am_michael');
    await tester.pumpWidget(_sheet(tts: false));
    expect(find.byKey(const ValueKey('voice-af_bella')), findsNothing);
  });

  testWidgets('never overflows while the keyboard is up, on a small screen, at large text', (tester) async {
    for (final keyboard in [0.0, 120.0, 300.0, 420.0]) {
      await tester.pumpWidget(_sheet(keyboard: keyboard, size: const Size(320, 568), textScale: 1.6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'keyboard $keyboard');
    }
  });

  testWidgets('the sheet scrolls so the voice section is reachable above the keyboard', (tester) async {
    await tester.pumpWidget(_sheet(keyboard: 300, size: const Size(360, 640)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('connection-tts')), 80, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('connection-tts')), findsOneWidget);
  });
}
