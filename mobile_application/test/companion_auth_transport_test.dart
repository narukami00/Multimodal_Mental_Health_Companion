import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/companion_auth.dart';
import 'package:solace_mobile/services/companion_http.dart';
import 'package:solace_mobile/services/journal_analysis_client.dart';

void main() {
  test(
    'cleartext LAN and unproven tunnel endpoints are blocked before reading credentials',
    () async {
      var tokenReads = 0;
      var requests = 0;
      final http = CompanionHttp(
        tokenProvider: ({required forceRefresh}) async {
          tokenReads++;
          return 'secret';
        },
        transport:
            ({
              required method,
              required uri,
              required headers,
              required body,
              required timeout,
            }) async {
              requests++;
              return (status: 200, body: '{}');
            },
      );
      for (final host in [
        '192.168.1.5',
        '100.88.46.59',
        'server.tailnet.ts.net',
      ]) {
        await expectLater(
          http.request(
            method: 'POST',
            uri: Uri.parse('http://$host/v1/sessions'),
          ),
          throwsA(isA<CompanionSecureConnectionRequired>()),
        );
      }
      expect(tokenReads, 0);
      expect(requests, 0);
    },
  );

  test(
    'TLS, loopback and exact explicitly trusted routes have separate policies',
    () {
      final policy = CompanionTransportPolicy(
        trustedPrivateHosts: {'my-private-server'},
      );
      for (final address in [
        'https://example.org:443',
        'wss://example.org:443',
        'http://localhost:8000',
        'ws://127.0.0.1:8000',
        'http://[::1]:8000',
        'http://my-private-server:8000',
      ]) {
        expect(() => policy.requireSecure(Uri.parse(address)), returnsNormally);
      }
      for (final address in [
        'http://my-private-server.evil:8000',
        'ws://100.88.46.59:8000',
        'https://user:secret@example.org',
        'ftp://localhost',
      ]) {
        expect(
          () => policy.requireSecure(Uri.parse(address)),
          throwsA(isA<CompanionSecureConnectionRequired>()),
        );
      }
      final base = companionHttpBase('https://example.org:8443', 8000);
      expect(base.toString(), 'https://example.org:8443');
      expect(
        base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws').scheme,
        'wss',
      );
    },
  );

  test('missing identity never sends a protected request', () async {
    var requests = 0;
    final http = CompanionHttp(
      tokenProvider: ({required forceRefresh}) async => null,
      transport:
          ({
            required method,
            required uri,
            required headers,
            required body,
            required timeout,
          }) async {
            requests++;
            return (status: 200, body: '{}');
          },
    );
    await expectLater(
      http.request(
        method: 'POST',
        uri: Uri.parse('http://localhost/v1/sessions'),
      ),
      throwsA(isA<CompanionSignInRequired>()),
    );
    expect(requests, 0);
  });

  test(
    '401 refreshes once and never falls back to an unprotected request',
    () async {
      final refreshes = <bool>[];
      final authorizations = <String?>[];
      final http = CompanionHttp(
        tokenProvider: ({required forceRefresh}) async {
          refreshes.add(forceRefresh);
          return forceRefresh ? 'fresh' : 'stale';
        },
        transport:
            ({
              required method,
              required uri,
              required headers,
              required body,
              required timeout,
            }) async {
              expect(uri.queryParameters.containsKey('token'), isFalse);
              authorizations.add(headers['Authorization']);
              return (status: 401, body: '{}');
            },
      );
      expect(
        (await http.request(
          method: 'GET',
          uri: Uri.parse('http://localhost/v1/models/stt'),
        )).status,
        401,
      );
      expect(refreshes, [false, true]);
      expect(authorizations, ['Bearer stale', 'Bearer fresh']);
    },
  );

  test(
    'journal modalities share issued lease; account change creates a new lease',
    () async {
      String? uid = 'alice';
      var issued = 0;
      final wireSessions = <String>[];
      final client = JournalAnalysisClient(
        baseUri: () async => Uri.parse('http://localhost:8000'),
        tokenProvider: ({required forceRefresh}) async =>
            uid == null ? null : 'token-$uid',
        userId: () => uid,
        transport:
            ({
              required method,
              required uri,
              required headers,
              required body,
              required timeout,
            }) async {
              expect(headers['Authorization'], 'Bearer token-$uid');
              if (uri.path == '/v1/sessions') {
                expect(jsonDecode(utf8.decode(body)), {'purpose': 'journal'});
                issued++;
                return (
                  status: 200,
                  body: jsonEncode({
                    'session_id': '$uid-$issued',
                    'expires_at':
                        DateTime.now()
                            .add(const Duration(hours: 1))
                            .millisecondsSinceEpoch ~/
                        1000,
                  }),
                );
              }
              wireSessions.add(
                uri.queryParameters['session_id'] ??
                    jsonDecode(utf8.decode(body))['session_id'] as String,
              );
              return (
                status: 200,
                body: jsonEncode({'transcript': 'hello', 'usable': 1}),
              );
            },
      );
      expect(await client.analyzeText('local-label', 'hello'), isNotNull);
      expect(await client.sendFrame('local-label', Uint8List(1)), isTrue);
      expect(issued, 1);
      uid = 'bob';
      expect(await client.analyzeText('local-label', 'hello'), isNotNull);
      expect(wireSessions, ['alice-1', 'alice-1', 'bob-2']);
      uid = null;
      expect(await client.analyzeText('local-label', 'hello'), isNull);
      expect(wireSessions.length, 3);
    },
  );
}
