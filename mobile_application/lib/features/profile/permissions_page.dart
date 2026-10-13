import 'package:flutter/material.dart';

import '../../core/models/consent.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../../services/app_permission_service.dart';
import '../checkin/check_in_mode_page.dart';
import '../consent/consent_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import 'phone_patterns_card.dart';

/// What Solace can access, what it does with it, and what it never collects.
///
/// Android owns these permissions, so every row reports the real state and
/// offers a way to the system screen that changes it. Nothing here pretends the
/// app can switch an OS permission itself.
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({this.permissions, this.phonePatterns, super.key});

  /// Injectable so the page can be exercised without the platform channel.
  final AppPermissionService? permissions;

  /// The opt-in phone patterns control. Without it the row is not shown.
  final PhonePatternsController? phonePatterns;

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  AppPermissionService get _permissions =>
      widget.permissions ?? AppPermissionService.instance;

  bool _notifications = false;
  bool _microphone = false;
  bool _camera = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final notifications = await _permissions.notificationsGranted();
    final microphone = await _permissions.microphoneGranted();
    final camera = await _permissions.cameraGranted();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _microphone = microphone;
      _camera = camera;
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
    final consent = CheckInModePage.consent;

    return Scaffold(
      backgroundColor: colors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const PageHero(
            scene: HeroScene.permissions,
            title: 'Permissions & privacy',
            subtitle: 'What Solace can use, and where it goes.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KitLabel('ON YOUR PHONE'),
                // The sentence that keeps this page honest: Android owns these, Solace only reports them.
                const KitCard(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
                  color: Color(0xFFEEF6FA),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF3F8FB5)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Android owns these settings. Solace can only show you their '
                          'state and take you to where they are changed.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4, color: Color(0xFF3A6A82)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else ...[
                  _PermissionRow(
                    key: const ValueKey('permission-notifications'),
                    icon: Icons.notifications_none_rounded,
                    color: const Color(0xFFD98A12),
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
                    color: const Color(0xFFD9674A),
                    title: 'Microphone',
                    grants: 'Voice check-ins and voice conversations.',
                    ifDenied: 'Text check-ins only, with the same features.',
                    granted: _microphone,
                    onOpenSettings: _openSettings,
                  ),
                  const SizedBox(height: 10),
                  _PermissionRow(
                    key: const ValueKey('permission-camera'),
                    icon: Icons.videocam_outlined,
                    color: const Color(0xFF6E73C8),
                    title: 'Camera',
                    grants: 'Video journals and video calls. Frames are read live and never saved.',
                    ifDenied: 'No camera in calls or journals. Everything else still works.',
                    granted: _camera,
                    onOpenSettings: _openSettings,
                  ),
                  const SizedBox(height: 10),
                  const _NeverAskedRow(),
                  if (widget.phonePatterns != null) ...[
                    const SizedBox(height: 10),
                    PhonePatternsCard(controller: widget.phonePatterns!),
                  ],
                ],
                if (consent != null) ...[
                  const KitLabel('WHAT YOU HAVE AGREED TO IN SOLACE'),
                  _ConsentCard(consent: consent),
                ],
                const KitLabel('WHERE YOUR DATA GOES'),
                const _LeavesDevice(),
                const SizedBox(height: 12),
                const _NotCollected(),
                const SizedBox(height: 22),
                const Text(
                  'Solace is a reflection space, not a medical or clinical '
                  'provider.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.5, color: Color(0xFFA2988A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The in-app choices (what Solace may read or send), as switches the person can flip back at any time.
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.consent});

  final ConsentController consent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: consent,
      builder: (context, _) {
        Widget row(IconData icon, Color color, String title, String sub, ConsentKey key) {
          return SettingRow(
            icon: icon,
            color: color,
            title: title,
            subtitle: sub,
            trailing: Switch(
              key: ValueKey('agree-${key.key}'),
              value: consent.isGranted(key),
              activeTrackColor: kitAmber,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              onChanged: (v) => v ? consent.grant(key) : consent.revoke(key),
            ),
          );
        }

        return KitCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Column(
            children: [
              row(Icons.graphic_eq_rounded, const Color(0xFFD9674A), 'Notice how I sound', 'Voice and words, read in memory.', ConsentKey.emotionEstimate),
              const Divider(height: 8, color: kitLine),
              row(Icons.face_retouching_natural_rounded, const Color(0xFF6E73C8), 'Notice my face', 'Only with the camera on, never saved.', ConsentKey.faceFeatures),
              const Divider(height: 8, color: kitLine),
              row(Icons.person_outline_rounded, const Color(0xFF4F8A52), 'Share a short profile with Sol', 'So replies can fit you.', ConsentKey.profileSnippet),
              const Divider(height: 8, color: kitLine),
              row(Icons.bookmark_border_rounded, const Color(0xFFB57A12), 'Let Sol remember moments', 'Only the ones you chose to keep.', ConsentKey.memoryMoments),
            ],
          ),
        );
      },
    );
  }
}

/// A tile for something Solace never asks for.
class _NeverAskedRow extends StatelessWidget {
  const _NeverAskedRow();

  @override
  Widget build(BuildContext context) {
    return const KitCard(
      key: ValueKey('permission-location'),
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          IconTile(icon: Icons.location_off_outlined, color: Color(0xFF4F8A52)),
          SizedBox(width: 14),
          Expanded(child: Text('Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kitInk))),
          StatusPill('Never asked', color: Color(0xFF4F8A52)),
        ],
      ),
    );
  }
}

/// The honest half: what genuinely leaves the device, as a short list with a symbol on each line.
class _LeavesDevice extends StatelessWidget {
  const _LeavesDevice();

  @override
  Widget build(BuildContext context) {
    return const KitCard(
      key: ValueKey('leaves-device'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT LEAVES THIS DEVICE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xFFBCAC8E)),
          ),
          SizedBox(height: 12),
          _FlowLine(
            icon: Icons.smartphone_rounded,
            color: Color(0xFF4F8A52),
            tag: 'STAYS',
            text: 'Your check-ins, journal and mood history are stored only on this device.',
          ),
          _FlowLine(
            icon: Icons.chat_bubble_outline_rounded,
            color: Color(0xFFD98A12),
            tag: 'SENT',
            text: 'Online chat sends your chat text to the Solace companion server for processing.',
          ),
          _FlowLine(
            icon: Icons.mic_none_rounded,
            color: Color(0xFFD9674A),
            tag: 'SENT',
            text: 'Voice check-ins and voice conversations send audio to the companion server so it can be transcribed.',
          ),
          _FlowLine(
            icon: Icons.videocam_outlined,
            color: Color(0xFF6E73C8),
            tag: 'LIVE',
            text: 'With face reading on, video calls and journals send live camera frames. They are read in memory and never saved.',
          ),
          _FlowLine(
            icon: Icons.groups_2_outlined,
            color: Color(0xFF4F8A52),
            tag: 'NEVER',
            text: 'Nothing is shared with anyone else, and no clinician is connected in this build.',
            last: true,
          ),
        ],
      ),
    );
  }
}

class _FlowLine extends StatelessWidget {
  const _FlowLine({required this.icon, required this.color, required this.tag, required this.text, this.last = false});

  final IconData icon;
  final Color color;
  final String tag;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4, color: Color(0xFF6E5F4A))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The other honest half: what we deliberately do not take.
class _NotCollected extends StatelessWidget {
  const _NotCollected();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('not-collected'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF7EB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD3E8D3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 17, color: Color(0xFF3F823B)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'WHAT SOLACE DOES NOT COLLECT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Color(0xFF3F823B)),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _NotLine(icon: Icons.location_off_outlined, text: 'Your location, contacts, messages or call history'),
          _NotLine(icon: Icons.visibility_off_outlined, text: 'What is inside any app, message or notification, even with phone patterns on'),
          _NotLine(icon: Icons.ads_click_outlined, text: 'Advertising identifiers or third-party analytics'),
          SizedBox(height: 2),
          Text(
            'These stay off by design. Phone patterns (screen time and which '
            'kind of app is open) are off unless you turn them on above, and '
            'stay on this phone.',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.45, color: Color(0xFF4F7A4B)),
          ),
        ],
      ),
    );
  }
}

class _NotLine extends StatelessWidget {
  const _NotLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: const Color(0xFFD3E8D3), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: const Color(0xFF3F823B)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.35, color: Color(0xFF3F6B3C))),
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
    required this.color,
    required this.title,
    required this.grants,
    required this.ifDenied,
    required this.granted,
    required this.onOpenSettings,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String grants;
  final String ifDenied;
  final bool granted;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return KitCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: icon, color: color),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kitInk))),
              granted ? const StatusPill('Allowed', color: Color(0xFF3F823B)) : const StatusPill('Not allowed', color: Color(0xFF7A6E5D)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            granted ? grants : ifDenied,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.45, color: Color(0xFF7B6A55)),
          ),
          const SizedBox(height: 4),
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
              label: const Text('Change in system settings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
