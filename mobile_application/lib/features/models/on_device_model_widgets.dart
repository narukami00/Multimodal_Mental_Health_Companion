import 'package:flutter/material.dart';

import '../../core/widgets/visual_kit.dart';
import '../../services/face_reading_choice.dart';
import '../../services/model_pack_store.dart';
import 'model_pack_controller.dart';

const _soft = Color(0xFF8A7A61);
const _warm = Color(0xFFFFB534);
const _ink = Color(0xFF3A3125);
const _good = Color(0xFF4E8A55);
const _trouble = Color(0xFFB4522C);

String megabytes(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

/// Asks before a model is taken off the phone. True when the person agreed.
Future<bool> confirmRemoveModel(BuildContext context, {required String title, required String body}) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('remove-model-dialog'),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(key: const ValueKey('remove-model-keep'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
        TextButton(key: const ValueKey('remove-model-confirm'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
      ],
    ),
  );
  return agreed ?? false;
}

/// One on-device model in the small panel on a journal page.
class OnDeviceModelRow {
  const OnDeviceModelRow({
    required this.store,
    required this.keyPrefix,
    required this.icon,
    required this.color,
    required this.title,
    required this.offer,
    required this.onText,
    required this.removeTitle,
    required this.removeBody,
    this.onInstalled,
    this.onRemoved,
  });

  final ModelPackStore store;
  final String keyPrefix;
  final IconData icon;
  final Color color;
  final String title;

  /// One line: what it is for and what it costs (shown while it is not on the phone).
  final String offer;

  /// One line shown while it is on the phone (worked out each time it is drawn).
  final String Function() onText;
  final String removeTitle;
  final String removeBody;

  /// Called after a successful download / after the person removed it.
  final VoidCallback? onInstalled;
  final VoidCallback? onRemoved;
}

/// The on-device models, grouped in one tidy card on a journal page: a row for each, with what it is for, its size, and a
/// button to get or remove it. The fuller explanation lives in Permissions & privacy.
class OnDeviceModelsPanel extends StatefulWidget {
  const OnDeviceModelsPanel({required this.rows, super.key});

  final List<OnDeviceModelRow> rows;

  @override
  State<OnDeviceModelsPanel> createState() => _OnDeviceModelsPanelState();
}

class _OnDeviceModelsPanelState extends State<OnDeviceModelsPanel> {
  late final List<ModelPackController> _controllers = [for (final r in widget.rows) ModelPackController(r.store)];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _remove(int i) async {
    final row = widget.rows[i];
    if (await confirmRemoveModel(context, title: row.removeTitle, body: row.removeBody)) {
      await _controllers[i].remove();
      row.onRemoved?.call();
    }
  }

  Future<void> _download(int i) async {
    await _controllers[i].download();
    if (_controllers[i].installed == true) widget.rows[i].onInstalled?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(_controllers),
      builder: (context, _) {
        if (_controllers.any((c) => c.installed == null)) return const SizedBox(height: 4);
        final allOn = _controllers.every((c) => c.installed!);
        return Container(
          key: const ValueKey('models-panel'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF2ECDD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(allOn ? Icons.check_circle_rounded : Icons.cloud_off_rounded, size: 16, color: allOn ? _good : _soft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      allOn ? 'Ready without the server' : 'Make this work without the server',
                      key: const ValueKey('models-panel-title'),
                      style: const TextStyle(fontSize: 12, letterSpacing: 0.4, fontWeight: FontWeight.w800, color: _soft),
                    ),
                  ),
                ],
              ),
              for (var i = 0; i < widget.rows.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: Color(0xFFF2ECDD)),
                const SizedBox(height: 6),
                _ModelRow(row: widget.rows[i], controller: _controllers[i], onRemove: () => _remove(i), onDownload: () => _download(i)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.row, required this.controller, required this.onRemove, required this.onDownload});

  final OnDeviceModelRow row;
  final ModelPackController controller;
  final VoidCallback onRemove;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final installed = c.installed ?? false;
    final prefix = row.keyPrefix;
    final sub = c.downloading ? null : (installed ? row.onText() : row.offer);
    return Column(
      key: ValueKey(installed ? '$prefix-on' : '$prefix-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(row.icon, size: 20, color: row.color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 2),
                  if (sub != null)
                    Text(sub, style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: _soft))
                  else ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      key: ValueKey('$prefix-progress'),
                      value: c.progress == 0 ? null : c.progress,
                      color: _warm,
                      backgroundColor: const Color(0xFFF2ECDD),
                    ),
                    const SizedBox(height: 4),
                    Text('Getting it… ${(c.progress * 100).round()}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _soft)),
                  ],
                ],
              ),
            ),
            if (!c.downloading)
              installed
                  ? TextButton(key: ValueKey('$prefix-remove'), onPressed: onRemove, child: const Text('Remove'))
                  : TextButton(key: ValueKey('$prefix-download'), onPressed: onDownload, child: const Text('Download')),
          ],
        ),
        if (c.message != null)
          Padding(
            padding: const EdgeInsets.only(left: 30, right: 8, bottom: 4),
            child: Text(c.message!, key: ValueKey('$prefix-message'), style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w700, color: _trouble)),
          ),
      ],
    );
  }
}

/// One model in Permissions & privacy: what it is for, what it costs, where it lives, and the buttons to get or remove it.
class OnDeviceModelCard extends StatefulWidget {
  const OnDeviceModelCard({
    required this.store,
    required this.keyPrefix,
    required this.icon,
    required this.color,
    required this.title,
    required this.what,
    required this.sizeText,
    required this.removeTitle,
    required this.removeBody,
    this.extra,
    this.onRemoved,
    super.key,
  });

  /// Called after the person removed the model from the phone.
  final VoidCallback? onRemoved;

  final ModelPackStore store;
  final String keyPrefix;
  final IconData icon;
  final Color color;
  final String title;
  final String what;
  final String sizeText;
  final String removeTitle;
  final String removeBody;

  /// Anything more for this model (for example the choice of where the camera is read); shown only while installed.
  final Widget? extra;

  @override
  State<OnDeviceModelCard> createState() => _OnDeviceModelCardState();
}

class _OnDeviceModelCardState extends State<OnDeviceModelCard> {
  late final ModelPackController _c = ModelPackController(widget.store);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    if (await confirmRemoveModel(context, title: widget.removeTitle, body: widget.removeBody)) {
      await _c.remove();
      widget.onRemoved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final installed = _c.installed ?? false;
        final status = _c.downloading
            ? 'Getting it… ${(_c.progress * 100).round()}%'
            : installed
                ? 'On this phone${_c.bytes == null ? '' : ' · ${megabytes(_c.bytes!)}'}'
                : 'Not on this phone';
        return KitCard(
          key: ValueKey('${widget.keyPrefix}-model-card'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, size: 22, color: widget.color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink))),
                  Text(status, key: ValueKey('${widget.keyPrefix}-status'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: installed ? _good : _soft)),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.what, style: const TextStyle(fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600, color: _soft)),
              const SizedBox(height: 6),
              Text(widget.sizeText, style: const TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w700, color: _soft)),
              if (_c.downloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(key: ValueKey('${widget.keyPrefix}-progress'), value: _c.progress == 0 ? null : _c.progress, color: _warm, backgroundColor: const Color(0xFFF2ECDD)),
              ],
              if (_c.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_c.message!, key: ValueKey('${widget.keyPrefix}-message'), style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w700, color: _trouble)),
                ),
              if (widget.extra != null && installed) ...[const SizedBox(height: 10), widget.extra!],
              Align(
                alignment: Alignment.centerRight,
                child: installed
                    ? TextButton(key: ValueKey('${widget.keyPrefix}-remove'), onPressed: _c.downloading ? null : _remove, child: const Text('Remove from this phone'))
                    : TextButton(key: ValueKey('${widget.keyPrefix}-download'), onPressed: _c.downloading ? null : _c.download, child: const Text('Download')),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Where should your face be read?" The server (as always) or this phone. Shown inside the camera models' card, so it can
/// only be chosen once the models are on the phone.
class FaceReadingChoiceControl extends StatelessWidget {
  const FaceReadingChoiceControl({required this.choice, super.key});

  final FaceReadingChoice choice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: choice,
      builder: (context, _) {
        Widget option(FaceReadingPlace place, String title, String detail) {
          final selected = choice.place == place;
          return InkWell(
            key: ValueKey('face-place-${place.name}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => choice.set(place),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFFF3D6) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? _warm : const Color(0xFFF2ECDD), width: selected ? 1.6 : 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: selected ? _warm : _soft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink)),
                        const SizedBox(height: 2),
                        Text(detail, style: const TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: _soft)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Where should your face be read?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 8),
              option(FaceReadingPlace.server, 'On the companion server', 'Video frames are sent to your own server, which reads them. This is how it has always worked.'),
              option(FaceReadingPlace.phone, 'On this phone', 'The phone reads your face itself. Only numbers describing it are sent, never pictures, and it keeps working without the server.'),
            ],
          );
      },
    );
  }
}
