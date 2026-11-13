import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/services/account_service.dart';
import 'support/account_fakes.dart';

void main() {
  late FakeAccountBackend backend;
  late MemoryAccountOwnership ownership;
  late AccountService service;
  setUp(() {
    backend = FakeAccountBackend();
    ownership = MemoryAccountOwnership();
    service = AccountService(backend: backend, ownership: ownership);
  });
  tearDown(() async {
    service.dispose();
    await backend.events.close();
  });

  test(
    'missing configuration completes without blocking local use or providing a token',
    () async {
      backend.unavailable = true;
      await service.initialize();
      expect(service.ready, isFalse);
      expect(service.identity, isNull);
      expect(await service.idToken(), isNull);
      await expectLater(service.google(), throwsA(isA<AccountProblem>()));
      backend.unavailable = false;
      await service.retryInitialization();
      expect(service.ready, isTrue);
    },
  );
  test(
    'sign-in binds identity; sign-out preserves binding and suppresses tokens',
    () async {
      await service.google();
      expect(service.identity?.uid, 'person-a');
      expect(ownership.uid, 'person-a');
      expect(await service.idToken(forceRefresh: true), 'fake-id-token');
      expect(backend.refreshRequested, isTrue);
      await service.signOut();
      expect(ownership.uid, 'person-a');
      expect(service.identity, isNull);
      expect(await service.idToken(), isNull);
      await service.signIn('a@example.org', 'password');
      expect(service.identity?.uid, 'person-a');
    },
  );
  test(
    'a different account cannot silently adopt existing local history',
    () async {
      await service.google();
      await service.signOut();
      backend.next = const AccountIdentity(uid: 'person-b');
      await expectLater(service.google(), throwsA(isA<AccountProblem>()));
      expect(ownership.uid, 'person-a');
      expect(service.identity, isNull);
      expect(backend.current, isNull);
      expect(await service.idToken(), isNull);
    },
  );
  test('a token resolving after sign-out is discarded', () async {
    await service.google();
    backend.tokenCompleter = Completer<String?>();
    final result = service.idToken();
    await Future<void>.delayed(Duration.zero);
    await service.signOut();
    backend.tokenCompleter!.complete('old-account-token');
    expect(await result, isNull);
  });
  test(
    'creating a new account is refused before contacting provider on a bound device',
    () async {
      ownership.uid = 'person-a';
      await service.initialize();
      await expectLater(
        service.create('new@example.org', 'password'),
        throwsA(isA<AccountProblem>()),
      );
      expect(backend.creates, 0);
    },
  );
  test(
    'restored provider identity must match this installation owner',
    () async {
      ownership.uid = 'person-a';
      backend.current = const AccountIdentity(uid: 'person-b');
      await service.initialize();
      expect(service.identity, isNull);
      expect(backend.signOuts, 1);
      expect(ownership.uid, 'person-a');
    },
  );
  test(
    'failed binding signs out candidate instead of exposing credentials',
    () async {
      ownership.refuseWrite = true;
      await expectLater(service.google(), throwsA(isA<AccountProblem>()));
      expect(service.identity, isNull);
      expect(await service.idToken(), isNull);
      expect(backend.current, isNull);
    },
  );
  test(
    'authentication errors have safe actionable text, not backend exception data',
    () async {
      backend.authError = FirebaseAuthException(
        code: 'invalid-credential',
        message: 'sensitive-provider-detail',
      );
      await expectLater(
        service.signIn('a@example.org', 'wrong'),
        throwsA(
          isA<AccountProblem>().having(
            (e) => e.message,
            'message',
            'The email or password is incorrect.',
          ),
        ),
      );
      expect(service.busy, isFalse);
      expect(ownership.uid, isNull);
    },
  );
  test(
    'deleting an account clears device ownership and requires re-auth when recent login is needed',
    () async {
      await service.signIn('a@example.org', 'password');
      expect(ownership.uid, 'person-a');
      backend.requireRecentLogin = true;
      await expectLater(
        service.deleteAccount(),
        throwsA(isA<AccountReauthRequired>()),
      );
      expect(ownership.uid, 'person-a');
      expect(service.identity?.uid, 'person-a');
      await service.reauthenticateWithPassword('password');
      expect(backend.reauths, 1);
      await service.deleteAccount();
      expect(backend.deletes, 1);
      expect(ownership.uid, isNull);
      expect(service.identity, isNull);
      expect(await service.idToken(), isNull);
    },
  );
}
