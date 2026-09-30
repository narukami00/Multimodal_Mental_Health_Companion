import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../../services/app_permission_service.dart';

/// What Solace can access, what it does with it, and what it never collects.
///
/// Android owns these permissions, so every row reports the real state and
/// offers a way to the system screen that changes it. Nothing here pretends the
/// app can switch an OS permission itself.
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({this.permissions, super.key});

  /// Injectable so the page can be exercised without the platform channel.
  final AppPermissionService? permissions;

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  AppPermissionService get _permissions =>
      widget.permissions ?? AppPermissionService.instance;

  bool _notifications = false;
  bool _microphone = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final notifications = await _permissions.notificationsGranted();
    final microphone = await _permissions.microphoneGranted();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _microphone = microphone;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    final opened = await _permissions.openSystemSettings();
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not open system settings.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    // The user may have changed something while away.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _buildHeader(context, colors),
                const SizedBox(height: 16),
                const Text(
                  'What Solace can access',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: Color(0xFF3A3125),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Android owns these settings. Solace can only show you their '
                  'state and take you to where they are changed.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: Color(0xFF7B6A55),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else ...[
                  _PermissionRow(
                    key: const ValueKey('permission-notifications'),
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    grants: 'Gentle check-in reminders at the time you choose.',
                    ifDenied: 'No reminders. Everything else still works.',
                    granted: _notifications,
                    onOpenSettings: _openSettings,
                  ),
                  const SizedBox(height: 10),
                  _PermissionRow(
                    key: const ValueKey('permission-microphone'),
                    icon: Icons.mic_none_rounded,
                    title: 'Microphone',
                    grants: 'Voice check-ins and voice conversations.',
                    ifDenied: 'Text check-ins only, with the same features.',
                    granted: _microphone,
                    onOpenSettings: _openSettings,
                  ),
                ],
                const SizedBox(height: 24),
                _buildLeavesDevice(colors),
                const SizedBox(height: 18),
                _buildNotCollected(colors),
                const SizedBox(height: 22),
                const Text(
                  'Solace is a reflection space, not a medical or clinical '
                  'provider.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: Color(0xFFA2988A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SolaceColors colors) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF3A3125),
            minimumSize: const Size(44, 44),
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'PERMISSIONS & DATA',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: Color(0xFFB9A98C),
          ),
        ),
      ],
    );
  }

  /// The honest half: what genuinely leaves the device.
  Widget _buildLeavesDevice(SolaceColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHAT LEAVES THIS DEVICE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFFBCAC8E),
            ),
          ),
          const SizedBox(height: 10),
          _bullet('Your check-ins, journal and mood history are stored only on '
              'this device.'),
          _bullet('Online chat sends your chat text to the Solace companion '
              'server for processing.'),
          _bullet('Voice check-ins and voice conversations send audio to the '
              'companion server so it can be transcribed.'),
          _bullet('Nothing is shared with anyone else, and no clinician is '
              'connected in this build.'),
        ],
      ),
    );
  }

  /// The other honest half: what we deliberately do not take.
  Widget _buildNotCollected(SolaceColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF7EB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD3E8D3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 17,
                color: Color(0xFF3F823B),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'WHAT SOLACE DOES NOT COLLECT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: Color(0xFF3F823B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bullet('Phone-use rhythm, screen time or app usage', dark: true),
          _bullet('Your location, contacts, messages or call history',
              dark: true),
          _bullet('Advertising identifiers or third-party analytics',
              dark: true),
          const SizedBox(height: 4),
          const Text(
            'These stay off by design. If phone-use patterns are ever added, '
            'they would be a separate choice you could decline.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF4F7A4B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text, {bool dark = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark
                    ? const Color(0xFF7BAE76)
                    : const Color(0xFFD3C8B2),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: dark
                    ? const Color(0xFF3F6B3C)
                    : const Color(0xFF7B6A55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One permission: real state, what it buys, and what happens without it.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.grants,
    required this.ifDenied,
    required this.granted,
    required this.onOpenSettings,
    super.key,
  });

  final IconData icon;
  final String title;
  final String grants;
  final String ifDenied;
  final bool granted;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2ECDD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DC),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 19, color: const Color(0xFFB57A12)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3B3327),
                  ),
                ),
              ),
              _statusChip(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            granted ? grants : ifDenied,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF7B6A55),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenSettings,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF96620C),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text(
                'Change in system settings',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: granted ? const Color(0xFFEBF7EB) : const Color(0xFFF4F1E7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        granted ? 'Allowed' : 'Not allowed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: granted
              ? const Color(0xFF3F823B)
              : const Color(0xFF7A6E5D),
        ),
      ),
    );
  }
}
