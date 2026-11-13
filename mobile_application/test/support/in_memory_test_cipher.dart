import 'dart:math';
import 'dart:typed_data';

import 'package:solace_mobile/services/secure_storage.dart';

/// Test-only authenticated cipher for Dart unit tests where the Android Keystore
/// platform channel is unavailable. Not used in production code.
class InMemoryTestCipher implements SecureCipher {
  InMemoryTestCipher({Uint8List? keyBytes})
      : _key = keyBytes ?? Uint8List.fromList(List<int>.generate(32, (i) => (i * 37 + 11) & 0xFF));

  final Uint8List _key;
  final Random _random = Random.secure();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> encrypt(Uint8List plaintext, {Uint8List? aad}) async {
    final iv = Uint8List.fromList(List<int>.generate(12, (_) => _random.nextInt(256)));
    final body = _xorKeystream(plaintext, iv);
    final mac = _computeMac(iv, body, aad);
    final out = Uint8List(5 + iv.length + body.length + mac.length);
    out[0] = 0x54; // 'T'
    out[1] = 0x53; // 'S'
    out[2] = 0x54; // 'T'
    out[3] = 1;
    out[4] = iv.length;
    out.setRange(5, 5 + iv.length, iv);
    out.setRange(5 + iv.length, 5 + iv.length + body.length, body);
    out.setRange(5 + iv.length + body.length, out.length, mac);
    return out;
  }

  @override
  Future<Uint8List> decrypt(Uint8List ciphertext, {Uint8List? aad}) async {
    if (ciphertext.length < 5 + 12 + 16 ||
        ciphertext[0] != 0x54 ||
        ciphertext[1] != 0x53 ||
        ciphertext[2] != 0x54 ||
        ciphertext[3] != 1) {
      throw SecureStorageException('Invalid test cipher envelope header');
    }
    final ivLen = ciphertext[4];
    if (ivLen != 12 || ciphertext.length < 5 + ivLen + 16) {
      throw SecureStorageException('Invalid test cipher IV length');
    }
    final iv = ciphertext.sublist(5, 5 + ivLen);
    final macStart = ciphertext.length - 16;
    final body = ciphertext.sublist(5 + ivLen, macStart);
    final actualMac = ciphertext.sublist(macStart);
    final expectedMac = _computeMac(iv, body, aad);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= actualMac[i] ^ expectedMac[i];
    }
    if (diff != 0) {
      throw SecureStorageException('Authentication tag mismatch');
    }
    return _xorKeystream(body, iv);
  }

  Uint8List _xorKeystream(Uint8List input, Uint8List iv) {
    final out = Uint8List(input.length);
    var state = 0x9E3779B9;
    for (final b in _key) {
      state = ((state * 1664525) + 1013904223 + b) & 0xFFFFFFFF;
    }
    for (final b in iv) {
      state = ((state * 1664525) + 1013904223 + b) & 0xFFFFFFFF;
    }
    for (var i = 0; i < input.length; i++) {
      state = ((state * 1664525) + 1013904223 + i) & 0xFFFFFFFF;
      out[i] = input[i] ^ ((state >> 16) & 0xFF);
    }
    return out;
  }

  Uint8List _computeMac(Uint8List iv, Uint8List body, Uint8List? aad) {
    final mac = Uint8List(16);
    var h1 = 0x811C9DC5;
    var h2 = 0x243F6A88;
    void mix(int byte) {
      h1 = ((h1 ^ byte) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 + byte + (h1 >> 8)) * 0x85EBCA6B) & 0xFFFFFFFF;
    }
    for (final b in _key) {
      mix(b);
    }
    for (final b in iv) {
      mix(b);
    }
    final aadBytes = aad ?? Uint8List(0);
    mix(aadBytes.length & 0xFF);
    for (final b in aadBytes) {
      mix(b);
    }
    mix(0xFF);
    for (final b in body) {
      mix(b);
    }
    for (var i = 0; i < 16; i++) {
      mix(i);
      mac[i] = ((h1 ^ (h2 >> (i % 16))) & 0xFF);
    }
    return mac;
  }
}
