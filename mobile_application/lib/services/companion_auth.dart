import 'account_service.dart';

typedef CompanionTokenProvider =
    Future<String?> Function({required bool forceRefresh});

/// Protected server features require a real signed-in Firebase identity.
/// A missing token leaves local self-care features available without sending data.
Future<String?> companionIdToken({bool forceRefresh = false}) =>
    AccountService.instance.idToken(forceRefresh: forceRefresh);

class CompanionSignInRequired implements Exception {
  const CompanionSignInRequired();

  @override
  String toString() => 'Sign in to use the companion server.';
}

class CompanionSecureConnectionRequired implements Exception {
  const CompanionSecureConnectionRequired();

  @override
  String toString() =>
      'Use an HTTPS companion server or connect through USB localhost. A private tunnel must be explicitly trusted in this app build.';
}

/// Bearer credentials may travel only over TLS, loopback, or an explicitly
/// declared private tunnel. An IP address alone never proves a tunnel exists.
class CompanionTransportPolicy {
  CompanionTransportPolicy({Set<String>? trustedPrivateHosts})
    : trustedPrivateHosts =
          trustedPrivateHosts ??
          const String.fromEnvironment('SOLACE_TRUSTED_PRIVATE_HOSTS')
              .split(',')
              .map((host) => host.trim().toLowerCase())
              .where((host) => host.isNotEmpty)
              .toSet();

  final Set<String> trustedPrivateHosts;

  void requireSecure(Uri uri) {
    final host = uri.host.toLowerCase();
    final scheme = uri.scheme.toLowerCase();
    if (uri.userInfo.isNotEmpty ||
        host.isEmpty ||
        !{'https', 'wss', 'http', 'ws'}.contains(scheme)) {
      throw const CompanionSecureConnectionRequired();
    }
    if (scheme == 'https' || scheme == 'wss') return;
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]' ||
        trustedPrivateHosts.contains(host)) {
      return;
    }
    throw const CompanionSecureConnectionRequired();
  }
}

/// Host settings accept a hostname/IP or an explicit HTTP(S) URL. The separate
/// port setting remains authoritative unless the URL includes its own port.
Uri companionHttpBase(String configuredHost, int port) {
  final raw = configuredHost.trim();
  if (!raw.contains('://')) return Uri(scheme: 'http', host: raw, port: port);
  final uri = Uri.parse(raw);
  if (!{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const CompanionSecureConnectionRequired();
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : port,
  );
}
