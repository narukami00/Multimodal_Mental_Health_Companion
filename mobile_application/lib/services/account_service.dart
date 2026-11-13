import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Online identity is separate from the profile and history kept on this device.
class AccountIdentity {
  const AccountIdentity({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.emailVerified = false,
  });
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;
}

class AccountProblem implements Exception {
  const AccountProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class AccountReauthRequired extends AccountProblem {
  const AccountReauthRequired()
    : super(
        'For your security, please sign in again before deleting your account.',
      );
}

abstract interface class AccountBackend {
  Future<void> initialize();
  AccountIdentity? get current;
  Stream<AccountIdentity?> get changes;
  Future<AccountIdentity> signIn(String email, String password);
  Future<AccountIdentity> create(String email, String password);
  Future<AccountIdentity> google();
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> verifyEmail();
  Future<void> reauthenticateWithPassword(String password);
  Future<void> reauthenticateWithGoogle();
  Future<void> deleteAccount();
  Future<String?> idToken({bool forceRefresh = false});
}

abstract interface class AccountOwnership {
  Future<String?> read();
  Future<void> bind(String uid);
  Future<void> clear();
}

class DeviceAccountOwnership implements AccountOwnership {
  static const key = 'account.device_owner_uid';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> bind(String uid) async {
    await (await SharedPreferences.getInstance()).setString(key, uid);
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}

/// Auth never gates loading local history. It does not synchronize or upload it.
/// A device's existing history cannot silently become another account's history.
class AccountService extends ChangeNotifier {
  AccountService({AccountBackend? backend, AccountOwnership? ownership})
    : _backend = backend ?? FirebaseAccountBackend(),
      _ownership = ownership ?? DeviceAccountOwnership();
  static final instance = AccountService();
  final AccountBackend _backend;
  final AccountOwnership _ownership;
  StreamSubscription<AccountIdentity?>? _subscription;
  Future<void>? _initialization;
  AccountIdentity? _identity;
  String? _owner;
  bool _ready = false;
  bool _initializing = false;
  bool _busy = false;
  bool _disposed = false;

  AccountIdentity? get identity => _identity;
  bool get ready => _ready;
  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get initialized => _initialization != null;
  String? get boundUid => _owner;

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _initializing = true;
    try {
      _owner = await _ownership.read();
      await _backend.initialize().timeout(const Duration(seconds: 12));
      final restored = _backend.current;
      // Only identities explicitly accepted on this installation are restored.
      if (restored != null && _owner != restored.uid) {
        await _backend.signOut();
      } else {
        _identity = restored;
      }
      _ready = true;
      _subscription = _backend.changes.listen(
        (value) {
          // A credential operation is not accepted until the ownership check below.
          if (value == null || value.uid == _owner) {
            _identity = value;
            _changed();
          }
        },
        onError: (Object _) {
          /* Local use survives transient auth failures. */
        },
      );
    } catch (_) {
      _ready = false;
    }
    _initializing = false;
    _changed();
  }

  Future<void> retryInitialization() async {
    if (_ready || _busy) {
      return;
    }
    if (_initializing) {
      return initialize();
    }
    _initialization = null;
    await initialize();
  }

  Future<AccountIdentity> _authenticate(
    Future<AccountIdentity> Function() action,
  ) async {
    if (_busy) {
      throw const AccountProblem(
        'Please wait for the current sign-in to finish.',
      );
    }
    _busy = true;
    _changed();
    try {
      await initialize();
      if (!_ready) {
        throw const AccountProblem(
          'Online sign-in is unavailable right now. You can continue on this device and try again later.',
        );
      }
      final candidate = await action();
      if (_owner != null && _owner != candidate.uid) {
        await _backend.signOut();
        _identity = null;
        throw const AccountProblem(
          'This device is connected to a different Solace account. Sign in with that account. Your local history has not changed. To use another account, save a copy and explicitly erase this device’s data first.',
        );
      }
      try {
        await _ownership.bind(candidate.uid);
      } catch (_) {
        await _backend.signOut();
        throw const AccountProblem(
          'The account could not be connected safely on this device. Your local history has not changed.',
        );
      }
      _owner = candidate.uid;
      _identity = candidate;
      return candidate;
    } on FirebaseAuthException catch (error) {
      throw AccountProblem(_authMessage(error.code));
    } on GoogleSignInException catch (error) {
      throw AccountProblem(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was cancelled.'
            : 'Google sign-in could not finish. Please try again.',
      );
    } on AccountProblem {
      rethrow;
    } catch (_) {
      throw const AccountProblem(
        'Could not connect. Check your internet connection and try again. Your local history is still here.',
      );
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<AccountIdentity> signIn(String email, String password) =>
      _authenticate(() => _backend.signIn(email.trim(), password));
  Future<AccountIdentity> create(
    String email,
    String password,
  ) => _authenticate(() {
    if (_owner != null) {
      throw const AccountProblem(
        'This device already has an account. Sign in to that account to keep its local history together.',
      );
    }
    return _backend.create(email.trim(), password);
  });
  Future<AccountIdentity> google() => _authenticate(_backend.google);

  Future<void> signOut() async {
    if (_busy) {
      return;
    }
    if (_ready) {
      await _backend.signOut();
    }
    _identity = null;
    // The binding remains: signing out does not reassign somebody's local data.
    _changed();
  }

  Future<void> resetPassword(String email) async {
    await initialize();
    if (!_ready) {
      throw const AccountProblem(
        'Online sign-in is unavailable. Try again later.',
      );
    }
    try {
      await _backend.resetPassword(email.trim());
    } on FirebaseAuthException catch (error) {
      throw AccountProblem(_authMessage(error.code));
    } catch (_) {
      throw const AccountProblem(
        'Could not request a reset email. Check your connection and try again.',
      );
    }
  }

  Future<void> verifyEmail() async {
    if (_identity == null) {
      return;
    }
    try {
      await _backend.verifyEmail();
    } catch (_) {
      throw const AccountProblem(
        'Could not send a verification email. Please try again later.',
      );
    }
  }

  Future<void> _runSignedIn(Future<void> Function() action) async {
    if (_busy) {
      throw const AccountProblem(
        'Please wait for the current account action to finish.',
      );
    }
    _busy = true;
    _changed();
    try {
      await initialize();
      if (!_ready || _identity == null) {
        throw const AccountProblem(
          'Sign in first to manage your online account.',
        );
      }
      await action();
    } on AccountProblem {
      rethrow;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        throw const AccountReauthRequired();
      }
      throw AccountProblem(_authMessage(error.code));
    } on GoogleSignInException catch (error) {
      throw AccountProblem(
        error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was cancelled.'
            : 'Google sign-in could not finish. Please try again.',
      );
    } catch (_) {
      throw const AccountProblem(
        'Could not finish. Check your connection and try again. Your local history is still here.',
      );
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> reauthenticateWithPassword(String password) =>
      _runSignedIn(() => _backend.reauthenticateWithPassword(password));

  Future<void> reauthenticateWithGoogle() =>
      _runSignedIn(_backend.reauthenticateWithGoogle);

  Future<void> deleteAccount() => _runSignedIn(() async {
    await _backend.deleteAccount();
    await _ownership.clear();
    _owner = null;
    _identity = null;
  });

  Future<String?> idToken({bool forceRefresh = false}) async {
    await initialize();
    if (!_ready || _identity == null || _identity!.uid != _owner || _busy) {
      return null;
    }
    final uid = _identity!.uid;
    if (_backend.current?.uid != uid) {
      return null;
    }
    try {
      final token = await _backend.idToken(forceRefresh: forceRefresh);
      if (_identity?.uid != uid ||
          _owner != uid ||
          _backend.current?.uid != uid ||
          _busy) {
        return null;
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

String _authMessage(String code) => switch (code) {
  'invalid-email' => 'Enter a valid email address.',
  'weak-password' => 'Choose a stronger password with at least 6 characters.',
  'email-already-in-use' =>
    'This email already has an account. Try signing in or reset your password.',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'The email or password is incorrect.',
  'network-request-failed' =>
    'Could not connect. Your local history is still available offline.',
  'too-many-requests' =>
    'Too many attempts. Please wait a little before trying again.',
  'user-disabled' =>
    'This account is disabled. Contact the app developer for help.',
  'operation-not-allowed' =>
    'This sign-in method is not available yet. Continue on this device or try another method.',
  'account-exists-with-different-credential' =>
    'Use the sign-in method you originally used for this email.',
  _ => 'Sign-in could not finish. Please try again.',
};

class FirebaseAccountBackend implements AccountBackend {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  bool _googleInitialized = false;
  @override
  Future<void> initialize() async {
    // Android uses google-services.json. Missing configuration is caught by the
    // service; it must never prevent offline startup or create a fake identity.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  AccountIdentity _identity(User user) => AccountIdentity(
    uid: user.uid,
    email: user.email,
    displayName: user.displayName,
    photoUrl: user.photoURL,
    emailVerified: user.emailVerified,
  );
  @override
  AccountIdentity? get current =>
      _auth.currentUser == null ? null : _identity(_auth.currentUser!);
  @override
  Stream<AccountIdentity?> get changes => _auth.idTokenChanges().map(
    (user) => user == null ? null : _identity(user),
  );
  @override
  Future<AccountIdentity> signIn(String email, String password) async =>
      _identity(
        (await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        )).user!,
      );
  @override
  Future<AccountIdentity> create(String email, String password) async =>
      _identity(
        (await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        )).user!,
      );
  @override
  Future<AccountIdentity> google() async {
    if (kIsWeb) {
      return _identity(
        (await _auth.signInWithPopup(GoogleAuthProvider())).user!,
      );
    }
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final authentication = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
    );
    return _identity((await _auth.signInWithCredential(credential)).user!);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  @override
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);
  @override
  Future<void> verifyEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    if (kIsWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    await user.delete();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _auth.currentUser?.getIdToken(forceRefresh);
}
