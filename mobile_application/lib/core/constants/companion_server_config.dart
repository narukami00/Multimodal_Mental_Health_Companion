import 'dart:io';
import 'package:flutter/foundation.dart';

/// Central configuration for Solace Companion server connectivity.
/// Supports Tailscale mesh VPN, MagicDNS, local Wi-Fi, and USB reverse localhost.
class CompanionServerConfig {
  const CompanionServerConfig._();

  /// Primary Tailscale IPv4 address of the PC server (desktop-cdej4vj).
  /// This IP is permanently assigned to the PC on the user's Tailnet and routes
  /// across cellular data, remote Wi-Fi, and local networks without USB tethering.
  static const String defaultTailscaleIp = '100.88.46.59';

  /// MagicDNS hostname for the server on Tailscale.
  static const String defaultMagicDns = 'desktop-cdej4vj.tailc05ab0.ts.net';

  /// Local home Wi-Fi fallback.
  static const String defaultLanIp = '192.168.0.38';

  /// USB adb reverse / emulator localhost fallback.
  static const String defaultLocalhost = '127.0.0.1';

  /// Companion server port (FastAPI).
  static const int defaultPort = 8000;

  /// Ordered candidate hosts tried automatically by [CompanionWebSocketService].
  static const List<String> candidateHosts = [
    defaultTailscaleIp,
    defaultMagicDns,
    defaultLanIp,
    defaultLocalhost,
  ];

  /// Preference key for saved companion server host.
  static const String prefKeyHost = 'companion_server_host';

  /// Preference key for saved companion server port.
  static const String prefKeyPort = 'companion_server_port';

  /// Preference key tracking Tailscale auto-migration flag.
  static const String prefKeyTailscaleMigrated = 'tailscale_migrated_v1';

  /// Whether current execution is within a Flutter unit/widget test.
  static bool get isTestEnvironment {
    try {
      return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }
}
