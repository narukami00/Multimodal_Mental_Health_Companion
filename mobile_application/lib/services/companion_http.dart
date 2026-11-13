import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'companion_auth.dart';

typedef CompanionHttpTransport =
    Future<({int status, String body})> Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      required List<int> body,
      required Duration timeout,
    });

class CompanionHttp {
  CompanionHttp({
    CompanionHttpTransport? transport,
    CompanionTokenProvider? tokenProvider,
    CompanionTransportPolicy? transportPolicy,
  }) : transport = transport ?? httpTransport,
       tokenProvider = tokenProvider ?? companionIdToken,
       transportPolicy = transportPolicy ?? CompanionTransportPolicy();

  final CompanionHttpTransport transport;
  final CompanionTokenProvider tokenProvider;
  final CompanionTransportPolicy transportPolicy;

  Future<({int status, String body})> request({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    List<int> body = const [],
    Duration timeout = const Duration(seconds: 8),
  }) async {
    transportPolicy.requireSecure(uri);
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await tokenProvider(forceRefresh: attempt == 1);
      if (token == null || token.isEmpty) throw const CompanionSignInRequired();
      final reply = await transport(
        method: method,
        uri: uri,
        headers: {...headers, 'Authorization': 'Bearer $token'},
        body: body,
        timeout: timeout,
      );
      if (reply.status != 401 || attempt == 1) return reply;
    }
    throw StateError('Unreachable authentication retry');
  }

  Future<({String id, DateTime expiresAt})> createSession(
    Uri base,
    String purpose,
  ) async {
    final reply = await request(
      method: 'POST',
      uri: base.replace(path: '/v1/sessions', query: ''),
      headers: const {'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode({'purpose': purpose})),
    );
    if (reply.status != 200 && reply.status != 201) {
      throw const HttpException('Unable to create server session');
    }
    final data = jsonDecode(reply.body) as Map<String, dynamic>;
    final id = data['session_id'];
    final expiry = data['expires_at'];
    if (id is! String || id.isEmpty || expiry is! num) {
      throw const FormatException('Invalid server session');
    }
    return (
      id: id,
      expiresAt: DateTime.fromMillisecondsSinceEpoch((expiry * 1000).round()),
    );
  }

  static Future<({int status, String body})> httpTransport({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int> body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.followRedirects =
          false; // Never forward credentials to a different server.
      headers.forEach(request.headers.set);
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(timeout);
      return (
        status: response.statusCode,
        body: await response.transform(utf8.decoder).join().timeout(timeout),
      );
    } finally {
      client.close(force: true);
    }
  }
}
