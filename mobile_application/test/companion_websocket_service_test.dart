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
  });
}
