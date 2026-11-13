import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/solace_palette.dart';
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
  bool _obscurePassword = true;
  bool _working = false;
  String? _message;
  String? _localPhoto;
  String? _googlePhoto;
  bool _clearPhoto = false;

  static const _sage = Color(0xFF3F9A7C);
  static const _fieldFill = Color(0xFFFFFBF0);
  static const _fieldBorder = Color(0xFFE7DBC0);

  InputDecoration _inputDecoration(
    String label, {
    IconData? icon,
    Widget? suffix,
  }) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: kitSoft,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: kitSoft),
        suffixIcon: suffix,
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kitAmber, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kitCoral),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kitCoral, width: 1.7),
        ),
      );

  ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
    backgroundColor: const Color(0xFF4A3728),
    foregroundColor: Colors.white,
    disabledBackgroundColor: const Color(0xFFD9CDBA),
    disabledForegroundColor: Colors.white70,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
  );

  ButtonStyle _secondaryButtonStyle() => OutlinedButton.styleFrom(
    foregroundColor: kitInk,
    backgroundColor: _fieldFill,
    side: const BorderSide(color: _fieldBorder),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
  );

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
        backgroundColor: const Color(0xFFFFFDF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete online account?',
          style: TextStyle(fontWeight: FontWeight.w800, color: kitInk),
        ),
        content: const Text(
          'This removes your Firebase sign-in. Your journal, forest and settings on this phone stay here unless you erase them in Profile -> Your data.',
          style: TextStyle(color: kitSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('account-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9534F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
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
          backgroundColor: const Color(0xFFFFFDF7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Confirm it is you',
            style: TextStyle(fontWeight: FontWeight.w800, color: kitInk),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please sign in again before deleting your online account.',
                style: TextStyle(color: kitSoft, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('account-reauth-password'),
                controller: passwordController,
                obscureText: true,
                decoration: _inputDecoration(
                  'Password',
                  icon: Icons.lock_outline_rounded,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('account-reauth-google'),
                style: _secondaryButtonStyle(),
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
              style: _primaryButtonStyle(),
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
  Widget build(BuildContext context) {
    final palette = SolaceColors.from(context);
    return Scaffold(
      backgroundColor: palette.background,
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
          Widget padded(Widget child, {double top = 0}) => Padding(
            padding: EdgeInsets.fromLTRB(20, top, 20, 0),
            child: child,
          );
          return ListView(
            padding: const EdgeInsets.only(bottom: 36),
            children: [
              PageHero(
                scene: HeroScene.privacy,
                title: identity == null ? 'Solace account' : 'Your account',
                subtitle: identity == null
                    ? 'Optional online sign-in · history stays local'
                    : 'Signed in on this device · local history only',
                height: 152,
              ),
              if (identity == null)
                padded(
                  top: 14,
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: _sage.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _sage.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 19,
                          color: _sage,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Firebase only handles sign-in. Your journals, forest and settings stay encrypted on this device unless you export them.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.38,
                              fontWeight: FontWeight.w600,
                              color: kitSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (identity == null) ...[
                if (!_service.ready)
                  padded(
                    top: 14,
                    KitCard(
                      color: const Color(0xFFFFF8E8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const IconTile(
                                icon: Icons.cloud_off_rounded,
                                color: kitAmber,
                                size: 38,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _service.initializing
                                      ? 'Checking online sign-in...'
                                      : 'Online sign-in unavailable',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: kitInk,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _service.initializing
                                ? 'Checking online sign-in. You can continue on this device at any time.'
                                : 'Online sign-in is unavailable until this app is configured and connected. You can keep using Solace on this device.',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: kitSoft,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: disabled || _service.initializing
                                  ? null
                                  : () => _run(_service.retryInitialization),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Try online sign-in again'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                padded(
                  top: 14,
                  KitCard(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _create
                              ? 'Create an account'
                              : 'Sign in with your account',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kitInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Your space, your choice — no history is uploaded.',
                          style: TextStyle(fontSize: 13, color: kitSoft),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: const ValueKey('account-google'),
                          style: _secondaryButtonStyle(),
                          onPressed: disabled || !_service.ready
                              ? null
                              : () => _run(
                                  () async => _prefill(await _service.google()),
                                ),
                          icon: const Icon(
                            Icons.login_rounded,
                            color: kitCoral,
                          ),
                          label: const Text('Continue with Google'),
                        ),
                      ],
                    ),
                  ),
                ),
                padded(
                  top: 12,
                  KitCard(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _create ? 'SIGN UP WITH EMAIL' : 'OR SIGN IN WITH EMAIL',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: kitMuted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const ValueKey('account-email'),
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            autocorrect: false,
                            decoration: _inputDecoration(
                              'Email',
                              icon: Icons.mail_outline_rounded,
                            ),
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
                            obscureText: _obscurePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [
                              _create
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: _inputDecoration(
                              'Password',
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                  color: kitMuted,
                                ),
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                              ),
                            ),
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
                            style: _primaryButtonStyle(),
                            onPressed: disabled || !_service.ready
                                ? null
                                : _emailAuth,
                            child: Text(
                              _create
                                  ? 'Create account'
                                  : 'Sign in with email',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                padded(
                  top: 8,
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
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
                              : 'New here? Create an account',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kitInk,
                          ),
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
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: kitSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                padded(
                  top: 14,
                  KitCard(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFFFFF), Color(0xFFF3FAF6)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const IconTile(
                              icon: Icons.verified_user_rounded,
                              color: _sage,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Connected',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: kitInk,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      StatusPill(
                                        identity.emailVerified
                                            ? 'Verified'
                                            : 'Unverified',
                                        color: identity.emailVerified
                                            ? _sage
                                            : kitAmber,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    identity.email ?? 'Solace account',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: kitSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kitLine),
                          ),
                          child: const Text(
                            'Local history stays on this phone. No cloud backup is enabled.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: kitSoft,
                            ),
                          ),
                        ),
                        if (!identity.emailVerified) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: _secondaryButtonStyle(),
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
                            icon: const Icon(
                              Icons.mark_email_read_outlined,
                              size: 18,
                            ),
                            label: const Text('Send verification email'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: KitLabel('PROFILE APPEARANCE'),
                ),
                padded(
                  KitCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'How should Solace greet you?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: kitInk,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Name and photo stay on this device and can be updated anytime.',
                          style: TextStyle(fontSize: 12.5, color: kitSoft),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: kitAmber.withValues(alpha: 0.7),
                                      width: 2,
                                    ),
                                    color: _fieldFill,
                                  ),
                                  child: CircleAvatar(
                                    radius: 30,
                                    backgroundColor: const Color(0xFFFFF3DC),
                                    foregroundImage: photo,
                                    onForegroundImageError:
                                        photo == null ? null : (_, _) {},
                                    child: const Icon(
                                      Icons.person_outline_rounded,
                                      size: 28,
                                      color: kitSoft,
                                    ),
                                  ),
                                ),
                                Material(
                                  color: const Color(0xFF4A3728),
                                  shape: const CircleBorder(),
                                  elevation: 1,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: disabled ? null : _pickPhoto,
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.photo_camera_outlined,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kitInk,
                                      backgroundColor: _fieldFill,
                                      side: const BorderSide(
                                        color: _fieldBorder,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: disabled ? null : _pickPhoto,
                                    icon: const Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Choose a photo'),
                                  ),
                                  if (_googlePhoto != null)
                                    TextButton(
                                      onPressed: disabled
                                          ? null
                                          : () => setState(
                                              () => _googlePhoto = null,
                                            ),
                                      child: const Text(
                                        'Skip suggested photo',
                                      ),
                                    ),
                                  if (_localPhoto != null)
                                    TextButton(
                                      onPressed: disabled
                                          ? null
                                          : () => setState(() {
                                              _localPhoto = null;
                                              _googlePhoto = null;
                                              _clearPhoto = true;
                                            }),
                                      child: const Text(
                                        'Remove photo',
                                        style: TextStyle(color: kitCoral),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                padded(
                  top: 12,
                  TextField(
                    key: const ValueKey('account-display-name'),
                    controller: _name,
                    maxLength: 24,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(
                      'Name or nickname (optional)',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                ),
                padded(
                  top: 10,
                  FilledButton.icon(
                    key: const ValueKey('account-save-profile'),
                    style: _primaryButtonStyle(),
                    onPressed: disabled ? null : _saveProfile,
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 19,
                    ),
                    label: const Text('Save and continue'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: KitLabel('SESSION & ACCOUNT SAFETY'),
                ),
                padded(
                  KitCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: SettingRow(
                      icon: Icons.logout_rounded,
                      color: kitAmber,
                      title: 'Sign out, keep local history',
                      subtitle:
                          'Only sign out here; your journals stay on this device.',
                      onTap: disabled
                          ? null
                          : () => _run(() async {
                              await _service.signOut();
                              _googlePhoto = null;
                              _password.clear();
                            }),
                    ),
                  ),
                ),
                padded(
                  top: 10,
                  KitCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: SettingRow(
                      key: const ValueKey('account-delete'),
                      icon: Icons.delete_outline_rounded,
                      color: const Color(0xFFD9534F),
                      title: 'Delete online account',
                      subtitle:
                          'Removes your Firebase sign-in; on-device data stays until you erase it.',
                      onTap: disabled ? null : _confirmDeleteAccount,
                    ),
                  ),
                ),
              ],
              if (disabled)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Center(
                    child: CircularProgressIndicator(color: kitAmber),
                  ),
                ),
              if (_message != null)
                padded(
                  top: 14,
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: kitAmber.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 19,
                          color: Color(0xFF9C6615),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _message!,
                            key: const ValueKey('account-message'),
                            semanticsLabel: _message,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: kitInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              padded(
                top: 18,
                Center(
                  child: OutlinedButton(
                    key: const ValueKey('account-offline'),
                    style: _secondaryButtonStyle(),
                    onPressed: disabled
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Continue on this device'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
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
      builder: (context, _) {
        final identity = account.identity;
        const sage = Color(0xFF3F9A7C);
        Future<void> openAccount() async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  AccountPage(profile: profile, service: account),
            ),
          );
          if (saved == true) onProfileSaved?.call();
        }

        return KitCard(
          onTap: openAccount,
          child: Row(
            children: [
              IconTile(
                icon: identity == null
                    ? Icons.person_add_alt_1_rounded
                    : Icons.verified_user_rounded,
                color: identity == null ? kitAmber : sage,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          identity == null
                              ? 'Optional online account'
                              : 'Your account',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: kitInk,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusPill(
                          identity == null ? 'Optional' : 'Connected',
                          color: identity == null ? kitAmber : sage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      identity?.email ??
                          'Use email or Google for online features while keeping history on this device.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: kitSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        key: const ValueKey('open-account'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE7DBC0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              identity == null
                                  ? 'Sign in or create account'
                                  : 'Manage account',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: kitInk,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: kitInk,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
