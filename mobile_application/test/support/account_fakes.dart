import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:solace_mobile/services/account_service.dart';

class MemoryAccountOwnership implements AccountOwnership {
  MemoryAccountOwnership([this.uid]);
  String? uid;
  bool refuseWrite = false;
  @override
  Future<String?> read() async => uid;
  @override
  Future<void> bind(String value) async {
    if (refuseWrite) throw StateError('storage unavailable');
    uid = value;
  }

  @override
  Future<void> clear() async {
    uid = null;
  }
}

class FakeAccountBackend implements AccountBackend {
  final events = StreamController<AccountIdentity?>.broadcast(sync: true);
  AccountIdentity next = const AccountIdentity(
    uid: 'person-a',
    email: 'a@example.org',
    displayName: 'Google Name',
    emailVerified: true,
  );
  bool unavailable = false;
  bool refreshRequested = false;
  int signOuts = 0;
  int creates = 0;
  int deletes = 0;
  int reauths = 0;
  bool requireRecentLogin = false;
  Object? authError;
  Completer<String?>? tokenCompleter;
  @override
  AccountIdentity? current;
  @override
  Stream<AccountIdentity?> get changes => events.stream;
  @override
  Future<void> initialize() async {
    if (unavailable) throw StateError('missing configuration');
  }

  Future<AccountIdentity> _auth() async {
    if (authError != null) throw authError!;
    current = next;
    events.add(current);
    return next;
  }

  @override
  Future<AccountIdentity> signIn(String email, String password) => _auth();
  @override
  Future<AccountIdentity> create(String email, String password) {
    creates++;
    return _auth();
  }

  @override
  Future<AccountIdentity> google() => _auth();
  @override
  Future<void> signOut() async {
    signOuts++;
    current = null;
    events.add(null);
  }

  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> verifyEmail() async {}
  @override
  Future<void> reauthenticateWithPassword(String password) async {
    if (authError != null) throw authError!;
    reauths++;
    requireRecentLogin = false;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    if (authError != null) throw authError!;
    reauths++;
    requireRecentLogin = false;
  }

  @override
  Future<void> deleteAccount() async {
    if (requireRecentLogin) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    deletes++;
    current = null;
    events.add(null);
  }
  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    refreshRequested = forceRefresh;
    return tokenCompleter != null
        ? tokenCompleter!.future
        : current == null
        ? null
        : 'fake-id-token';
  }
}
