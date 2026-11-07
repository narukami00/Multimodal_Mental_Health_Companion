import 'package:flutter/material.dart';

import '../../core/widgets/visual_kit.dart';
import '../footprint/phone_patterns_controller.dart';

/// The "Phone patterns" row on the permissions page.
///
/// Off until the person turns it on, and every state says what is and is not
/// being read. Android's usage access is a switch Android owns, so this reports
/// its real state and re-checks it whenever the app comes back to the
/// foreground: someone can turn it off in system settings without telling
/// Solace, and the card must not go on claiming otherwise.
class PhonePatternsCard extends StatefulWidget {
  const PhonePatternsCard({required this.controller, super.key});

  final PhonePatternsController controller;

  @override
  State<PhonePatternsCard> createState() => _PhonePatternsCardState();
}

class _PhonePatternsCardState extends State<PhonePatternsCard>
    with WidgetsBindingObserver {
  int _storedDays = 0;

  PhonePatternsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    await _controller.refresh();
    final days = await _controller.storedDayCount();
    if (mounted) setState(() => _storedDays = days);
  }

  Future<void> _turnOn() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DisclosureDialog(),
    );
    if (agreed != true || !mounted) return;
    final opened = await _controller.turnOn();
    if (!mounted) return;
    if (!opened) {
      _tell('Could not open Android settings. Usage access is under '
          'Settings, Apps, Special access.');
    }
  }

  Future<void> _turnOff() async {
    var deleteStored = false;
    if (_storedDays > 0) {
      final choice = await showDialog<_TurnOffChoice>(
        context: context,
        builder: (context) => _TurnOffDialog(days: _storedDays),
      );
      if (choice == null || !mounted) return;
      deleteStored = choice == _TurnOffChoice.deleteToo;
    }
    await _controller.turnOff(deleteStored: deleteStored);
    await _reload();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete stored phone patterns?'),
        content: Text(
          'This removes $_storedDays ${_storedDays == 1 ? 'day' : 'days'} of '
          'patterns from this phone. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('phone-patterns-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.deleteStored();
    await _reload();
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final status = _controller.status;
    final (chip, chipOn, body) = switch (status) {
      PhonePatternsStatus.off => (
        'Off',
        false,
        'Nothing is read. Enable to keep screen time and app categories on this phone.',
      ),
      PhonePatternsStatus.needsAndroidAccess => (
        'Needs access',
        false,
        'Nothing is read until you allow usage access in Android.',
      ),
      PhonePatternsStatus.on => (
        'On',
        true,
        'Screen time and app categories stay on this phone. App contents, messages and notifications are never read.',
      ),
    };

    return KitCard(
      key: const ValueKey('permission-phone-patterns'),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.phone_android_rounded,
                color: Color(0xFFB57A12),
                size: 38,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Phone patterns',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3B3327),
                  ),
                ),
              ),
              Flexible(
                child: StatusPill(
                  chip,
                  color: chipOn ? const Color(0xFF3F823B) : kitSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: Color(0xFF7B6A55),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              if (status == PhonePatternsStatus.off)
                _action(
                  'phone-patterns-turn-on',
                  'Turn on…',
                  _turnOn,
                  Icons.toggle_on_outlined,
                ),
              if (status == PhonePatternsStatus.needsAndroidAccess)
                _action(
                  'phone-patterns-open-settings',
                  'Open Android settings',
                  () async {
                    final opened = await _controller.openAndroidSettings();
                    if (!opened && mounted) {
                      _tell('Could not open Android settings.');
                    }
                  },
                  Icons.open_in_new_rounded,
                ),
              if (status != PhonePatternsStatus.off)
                _action(
                  'phone-patterns-turn-off',
                  'Turn off',
                  _turnOff,
                  Icons.toggle_off_outlined,
                ),
              if (_storedDays > 0)
                _action(
                  'phone-patterns-delete',
                  'Delete stored patterns ($_storedDays '
                      '${_storedDays == 1 ? 'day' : 'days'})',
                  _delete,
                  Icons.delete_outline_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    String key,
    String label,
    VoidCallback onPressed,
    IconData icon,
  ) {
    return TextButton.icon(
      key: ValueKey(key),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// What turning it on means, said before it is turned on.
class _DisclosureDialog extends StatelessWidget {
  const _DisclosureDialog();

  @override
  Widget build(BuildContext context) {
    Widget point(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 10),
            child: Icon(Icons.circle, size: 5, color: Color(0xFFB9A98C)),
          ),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );

    return AlertDialog(
      title: const Text('Notice your phone rhythm?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            point(
              'Solace reads when your screen is on, when you unlock it, and '
              'which kind of app is open, such as social or video.',
            ),
            point(
              'It never reads what is inside an app, a message or a '
              'notification.',
            ),
            point(
              'It is turned into a few numbers per day and kept only on this '
              'phone. Nothing is sent anywhere.',
            ),
            point(
              'Android will ask you to switch on usage access for Solace. You '
              'can switch it off there, or here, at any time.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('phone-patterns-not-now'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          key: const ValueKey('phone-patterns-agree'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn on'),
        ),
      ],
    );
  }
}

enum _TurnOffChoice { keepStored, deleteToo }

class _TurnOffDialog extends StatelessWidget {
  const _TurnOffDialog({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Turn off phone patterns?'),
      content: Text(
        'Solace will stop reading. Delete the $days '
        '${days == 1 ? 'day' : 'days'} already stored on this phone as well?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('phone-patterns-keep'),
          onPressed: () => Navigator.of(context).pop(_TurnOffChoice.keepStored),
          child: const Text('Keep them'),
        ),
        TextButton(
          key: const ValueKey('phone-patterns-delete-too'),
          onPressed: () => Navigator.of(context).pop(_TurnOffChoice.deleteToo),
          child: const Text('Delete them'),
        ),
      ],
    );
  }
}
