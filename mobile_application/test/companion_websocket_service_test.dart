import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/companion_websocket_service.dart';

void main() {
  group('CompanionWebSocketService Unit Tests', () {
    test('initial state is disconnected with null latency', () {
      final service = CompanionWebSocketService();
      expect(service.status, CompanionConnectionStatus.disconnected);
      expect(service.lastLatencyMs, isNull);
      expect(service.sessionId, isNull);
      service.dispose();
    });

    test('manual disconnect cancels timers and updates status', () async {
      final service = CompanionWebSocketService();
      await service.disconnect();
      expect(service.status, CompanionConnectionStatus.disconnected);
      service.dispose();
    });

    test('configuration properties can be initialized or updated', () {
      final service = CompanionWebSocketService(
        host: '192.168.1.100',
        port: 8443,
        token: 'custom-token',
      );
      expect(service.host, '192.168.1.100');
      expect(service.port, 8443);
      expect(service.token, 'custom-token');
      service.dispose();
    });

    test('failed connection transitions cleanly to error without infinite reconnect loop', () async {
      // Point to an invalid unreachable port
      final service = CompanionWebSocketService(
        host: '127.0.0.1',
        port: 59999,
      );
      await service.connect();
      expect(service.status, CompanionConnectionStatus.error);
      expect(service.lastErrorMessage, isNotNull);

      // Subsequent connect call to another invalid port should also transition to error without hanging
      await service.connect(customPort: 59998);
      expect(service.status, CompanionConnectionStatus.error);
      expect(service.lastErrorMessage, isNotNull);

      service.dispose();
    });
  });

  group('session.configure memory block', () {
    test('is absent when nothing was agreed to, so the server treats it as none', () {
      final payload = CompanionWebSocketService.buildSessionConfigurePayload(
        sessionId: 's1',
        mode: 'chat_voice_playback',
      );
      expect(payload.containsKey('memory'), isFalse);
      expect(payload['type'], 'session.configure');
    });

    test('carries the snippet and moments exactly as given', () {
      final payload = CompanionWebSocketService.buildSessionConfigurePayload(
        sessionId: 's1',
        mode: 'chat_voice_playback',
        memory: const {
          'v': 1,
          'profile_snippet': 'Prefers a gentle tone.',
          'memory_facts': ['Tea with my sister.'],
        },
      );
      expect(payload['memory'], {
        'v': 1,
        'profile_snippet': 'Prefers a gentle tone.',
        'memory_facts': ['Tea with my sister.'],
      });
    });

    test('the provider is only read when a configure is built', () {
      var reads = 0;
      CompanionWebSocketService.memoryProvider = () {
        reads++;
        return null;
      };
      addTearDown(() => CompanionWebSocketService.memoryProvider = null);

      final service = CompanionWebSocketService();
      expect(reads, 0);
      service.dispose();
    });
  });
}
