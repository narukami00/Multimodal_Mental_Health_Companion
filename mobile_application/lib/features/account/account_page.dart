import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/widgets/visual_kit.dart';
import '../../services/account_service.dart';
import '../profile/profile_controller.dart';

/// One optional online account; local journals are never uploaded by this page.
class AccountPage extends StatefulWidget {
  const AccountPage({required this.profile, this.service, super.key});
  final ProfileController profile;
  final AccountService? service;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AccountService get _service => widget.service ?? AccountService.instance;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _create = false;
  bool _working = false;
  String? _message;
  String? _localPhoto;
  String? _googlePhoto;
  bool _clearPhoto = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.profile.profile.displayName ?? '';
    _localPhoto = widget.profile.profile.avatarPath;
    _service.initialize().then((_) {
      final identity = _service.identity;
      if (identity != null) _prefill(identity);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } on AccountProblem catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not finish. Your local history has not changed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  void _prefill(AccountIdentity identity) {
    if (!mounted) return;
    setState(() {
      if (_name.text.trim().isEmpty) _name.text = identity.displayName ?? '';
      if (_localPhoto == null) _googlePhoto = identity.photoUrl;
    });
  }

  Future<void> _emailAuth() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await _run(() async {
      final identity = _create
          ? await _service.create(_email.text, _password.text)
          : await _service.signIn(_email.text, _password.text);
      _password.clear();
      _prefill(identity);
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (photo != null && mounted) {
        setState(() {
          _localPhoto = photo.path;
          _googlePhoto = null;
          _clearPhoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not open your photos. You can add a photo later.',
        );
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete online account?'),
        content: const Text(
          'This removes your Firebase sign-in. Your journal, forest and settings on this phone stay here unless you erase them in Profile -> Your data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('account-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _attemptDelete();
  }

  Future<void> _attemptDelete() async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    var needsReauth = false;
    try {
      await _service.deleteAccount();
      _googlePhoto = null;
      _password.clear();
      if (mounted) {
        setState(() {
          _message =
              'Your online account was deleted. Your local history is still on this device.';
        });
      }
    } on AccountReauthRequired {
      needsReauth = true;
    } on AccountProblem catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not delete the account. Your local history has not changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (needsReauth && mounted) {
      final reauthed = await _promptReauth();
      if (reauthed && mounted) {
        await _attemptDelete();
      }
    }
  }

  Future<bool> _promptReauth() async {
    final passwordController = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm it is you'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please sign in again before deleting your online account.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('account-reauth-password'),
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('account-reauth-google'),
                onPressed: () async {
                  try {
                    await _service.reauthenticateWithGoogle();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  } on AccountProblem catch (error) {
                    if (mounted) setState(() => _message = error.message);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(false);
                    }
                  }
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Confirm with Google'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('account-reauth-submit'),
              onPressed: () async {
                final pwd = passwordController.text;
                if (pwd.isEmpty) return;
                try {
                  await _service.reauthenticateWithPassword(pwd);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } on AccountProblem catch (error) {
                  if (mounted) setState(() => _message = error.message);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(false);
                  }
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      return result == true;
    } finally {
      passwordController.dispose();
    }
  }

  Future<void> _saveProfile() => _run(() async {
    String? path = _localPhoto;
    if (_googlePhoto != null) {
      path = await _saveGooglePhoto(_googlePhoto!);
      if (path == null) {
        if (mounted) {
          setState(
            () => _message =
                'Your account is connected, but the photo could not be saved. Choose a photo or remove the suggestion and continue.',
          );
        }
        return;
      }
    } else if (path != null && path != widget.profile.profile.avatarPath) {
      path = await copyProfilePhoto(File(path));
    }
    await widget.profile.saveIdentity(
      displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      avatarPath: path,
      clearDisplayName: _name.text.trim().isEmpty,
      clearAvatarPath: _clearPhoto,
    );
    if (mounted) Navigator.of(context).pop(true);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your Solace account')),
    body: ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final identity = _service.identity;
        final disabled = _working || _service.busy;
        final ImageProvider? photo =
            _localPhoto != null && File(_localPhoto!).existsSync()
            ? FileImage(File(_localPhoto!))
            : _googlePhoto != null
            ? NetworkImage(_googlePhoto!)
            : null;
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              'Your space, your choice',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'An account connects online features. Firebase handles sign-in. Your journal, forest and settings stay on this device. Signing in does not upload or restore your history.',
            ),
            const SizedBox(height: 18),
            if (identity == null) ...[
              if (!_service.ready) ...[
                Text(
                  _service.initializing
                      ? 'Checking online sign-in. You can continue on this device at any time.'
                      : 'Online sign-in is unavailable until this app is configured and connected. You can keep using Solace on this device.',
                ),
                TextButton(
                  onPressed: disabled || _service.initializing
                      ? null
                      : () => _run(_service.retryInitialization),
                  child: const Text('Try online sign-in again'),
                ),
              ],
              OutlinedButton.icon(
                key: const ValueKey('account-google'),
                onPressed: disabled || !_service.ready
                    ? null
                    : () => _run(() async => _prefill(await _service.google())),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 14),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('account-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          value != null &&
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(value.trim())
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('account-password'),
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        _create
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your password.'
                          : _create && value.length < 6
                          ? 'Use at least 6 characters.'
                          : null,
                      onFieldSubmitted: (_) {
                        if (!disabled && _service.ready) _emailAuth();
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('account-email-submit'),
                      onPressed: disabled || !_service.ready
                          ? null
                          : _emailAuth,
                      child: Text(
                        _create ? 'Create account' : 'Sign in with email',
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () => setState(() {
                        _create = !_create;
                        _message = null;
                      }),
                child: Text(
                  _create
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an email account',
                ),
              ),
              TextButton(
                onPressed: disabled || !_service.ready
                    ? null
                    : () => _run(() async {
                        if (_email.text.trim().isEmpty) {
                          throw const AccountProblem(
                            'Enter your email address first.',
                          );
                        }
                        await _service.resetPassword(_email.text);
                        if (mounted) {
                          setState(
                            () => _message =
                                'If an account uses this address, a password reset email will arrive.',
                          );
                        }
                      }),
                child: const Text('Forgot password?'),
              ),
            ] else ...[
              KitCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connected',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(identity.email ?? 'Solace account'),
                    const Text(
                      'Local history stays on this phone. No cloud backup is enabled.',
                    ),
                    if (!identity.emailVerified)
                      TextButton(
                        onPressed: disabled
                            ? null
                            : () => _run(() async {
                                await _service.verifyEmail();
                                if (mounted) {
                                  setState(
                                    () => _message =
                                        'Verification email requested. Check your inbox.',
                                  );
                                }
                              }),
                        child: const Text('Send verification email'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'How should Solace greet you?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const Text(
                'Name and photo are optional. You can change these on your profile later.',
              ),
              const SizedBox(height: 14),
              Center(
                child: CircleAvatar(
                  radius: 40,
                  foregroundImage: photo,
                  onForegroundImageError: photo == null ? null : (_, _) {},
                  child: const Icon(Icons.person_outline_rounded, size: 38),
                ),
              ),
              TextButton.icon(
                onPressed: disabled ? null : _pickPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Choose a photo'),
              ),
              if (_googlePhoto != null)
                TextButton(
                  onPressed: disabled
                      ? null
                      : () => setState(() => _googlePhoto = null),
                  child: const Text('Continue without suggested photo'),
                ),
              if (_localPhoto != null)
                TextButton(
                  onPressed: disabled ? null : () => setState(() {
                    _localPhoto = null;
                    _googlePhoto = null;
                    _clearPhoto = true;
                  }),
                  child: const Text('Remove photo from my profile'),
                ),
              TextField(
                key: const ValueKey('account-display-name'),
                controller: _name,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name or nickname (optional)',
                ),
              ),
              FilledButton(
                key: const ValueKey('account-save-profile'),
                onPressed: disabled ? null : _saveProfile,
                child: const Text('Save and continue'),
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () => _run(() async {
                        await _service.signOut();
                        _googlePhoto = null;
                        _password.clear();
                      }),
                child: const Text('Sign out, keep local history'),
              ),
              TextButton(
                key: const ValueKey('account-delete'),
                onPressed: disabled ? null : _confirmDeleteAccount,
                child: const Text('Delete online account'),
              ),
            ],
            if (disabled)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _message!,
                  key: const ValueKey('account-message'),
                  semanticsLabel: _message,
                ),
              ),
            const SizedBox(height: 10),
            TextButton(
              key: const ValueKey('account-offline'),
              onPressed: disabled
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Continue on this device'),
            ),
          ],
        );
      },
    ),
  );
}

/// Also used by optional onboarding photo selection; no account required.
Future<String> copyProfilePhoto(File source) async {
  final dir = await getApplicationDocumentsDirectory();
  final target = File(
    '${dir.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await source.copy(target.path);
  return target.path;
}

Future<String?> _saveGooglePhoto(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final response = await (await client.getUrl(
      uri,
    )).close().timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 ||
        !(response.headers.contentType?.mimeType.startsWith('image/') ?? false)) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 5 * 1024 * 1024) return null;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

class AccountEntryCard extends StatelessWidget {
  const AccountEntryCard({
    required this.profile,
    this.service,
    this.onProfileSaved,
    super.key,
  });
  final ProfileController profile;
  final AccountService? service;
  final VoidCallback? onProfileSaved;
  @override
  Widget build(BuildContext context) {
    final account = service ?? AccountService.instance;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) => KitCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              account.identity == null
                  ? 'Optional online account'
                  : 'Your account',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              account.identity?.email ??
                  'Use email or Google for online features. You can also stay on this device.',
            ),
            TextButton.icon(
              key: const ValueKey('open-account'),
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        AccountPage(profile: profile, service: account),
                  ),
                );
                if (saved == true) onProfileSaved?.call();
              },
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(
                account.identity == null
                    ? 'Sign in or create account'
                    : 'Manage account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
