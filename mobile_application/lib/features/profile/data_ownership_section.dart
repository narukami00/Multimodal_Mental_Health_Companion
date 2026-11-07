import 'package:flutter/material.dart';

import '../../core/widgets/visual_kit.dart';
import '../../domain/export/backup.dart';
import '../../services/data_ownership.dart';

/// Take a copy, bring a copy back, or erase everything: three plain rows. Shown in Permissions & privacy and in
/// Everything Solace keeps, so it is easy to find from either.
class DataOwnershipSection extends StatefulWidget {
  const DataOwnershipSection({this.service, super.key});

  /// Injectable (tests); the app uses the real one.
  final DataOwnership? service;

  @override
  State<DataOwnershipSection> createState() => _DataOwnershipSectionState();
}

class _DataOwnershipSectionState extends State<DataOwnershipSection> {
  bool _busy = false;

  DataOwnership get _service => widget.service ?? DataOwnership.instance;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await _service.exportBackup();
      if (!mounted) return;
      if (outcome == SaveOutcome.saved) _say('Your copy is saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await _service.pickBackup();
      if (!mounted || picked.isCancelled) return;
      final problem = picked.problem;
      if (problem != null) {
        _say(switch (problem) {
          BackupProblem.notABackup => 'That file is not a Solace copy.',
          BackupProblem.tooNew => 'That copy was made by a newer Solace. Update the app, then try again.',
          BackupProblem.damaged => 'That copy looks damaged, so nothing was changed.',
        });
        return;
      }
      final backup = picked.backup!;
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bring this copy back?'),
          content: Text(_importBody(backup)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              key: const ValueKey('import-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace and restart'),
            ),
          ],
        ),
      );
      if (sure == true) await _service.restore(backup);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _erase() async {
    if (_busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase everything?'),
        content: const Text(
          'This removes every check-in, journal entry, chat, moment, your forest and all your choices from this '
          'phone, then starts Solace fresh. It cannot be undone.\n\nSave a copy first if you might want any of it back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep my data')),
          FilledButton(
            key: const ValueKey('erase-confirm'),
            style: FilledButton.styleFrom(backgroundColor: kitCoral),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.eraseEverything();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _importBody(Backup backup) {
    final when = backup.createdAt;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final made = when == null ? 'an earlier day' : '${when.day} ${months[when.month - 1]} ${when.year}';
    final holds = backup.summary.sentence;
    return 'This copy was made on $made${holds == null ? '' : ' and holds $holds'}.\n\n'
        'Bringing it back replaces everything on this phone now, then Solace restarts. '
        'If you want to keep what is here, save a copy first.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitLabel('TAKE IT, MOVE IT, OR ERASE IT'),
        KitCard(
          key: const ValueKey('data-ownership'),
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          child: Column(
            children: [
              SettingRow(
                key: const ValueKey('data-export'),
                icon: Icons.ios_share_rounded,
                color: kitAmber,
                title: 'Save a copy',
                subtitle: 'Everything on this phone, as one file you keep.',
                onTap: _export,
              ),
              const Divider(height: 8, color: kitLine),
              SettingRow(
                key: const ValueKey('data-import'),
                icon: Icons.file_download_outlined,
                color: const Color(0xFF6E73C8),
                title: 'Bring a copy back',
                subtitle: 'From a Solace copy, on this phone or a new one.',
                onTap: _import,
              ),
              const Divider(height: 8, color: kitLine),
              SettingRow(
                key: const ValueKey('data-erase'),
                icon: Icons.delete_outline_rounded,
                color: kitCoral,
                title: 'Erase everything',
                subtitle: 'Removes it all from this phone and starts fresh.',
                onTap: _erase,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            'A copy is plain text and holds your own words, so keep it somewhere private. Recordings still waiting '
            'for your server and the downloaded models are not part of it.',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.5, color: kitMuted),
          ),
        ),
      ],
    );
  }
}
