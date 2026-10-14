import 'package:flutter/material.dart';

import '../../core/constants/companion_server_config.dart';
import '../../core/widgets/visual_kit.dart';
import '../../services/companion_websocket_service.dart';

/// The voices the server currently offers, as (id, short name).
const connectionVoices = [
  ('af_heart', 'Heart'),
  ('af_bella', 'Bella'),
  ('af_sarah', 'Sarah'),
  ('am_michael', 'Michael'),
];

/// Where Sol's server is, whether it is reachable, and how Sol speaks.
///
/// Built to survive the keyboard: the whole sheet scrolls and is capped to the
/// screen, so opening it while the keyboard is still going down never overflows
/// (the old column did, for a frame). The page owns the connection and the
/// stored settings; this only shows them and reports what the person chose.
class ConnectionSheetView extends StatefulWidget {
  const ConnectionSheetView({
    required this.initialHost,
    required this.initialPort,
    required this.status,
    required this.latencyMs,
    required this.ttsEnabled,
    required this.voiceId,
    required this.onConnect,
    required this.onDisconnect,
    required this.onPing,
    required this.onTtsChanged,
    required this.onVoiceChanged,
    this.errorMessage,
    super.key,
  });

  final String initialHost;
  final int initialPort;
  final CompanionConnectionStatus status;
  final int? latencyMs;
  final String? errorMessage;
  final bool ttsEnabled;
  final String voiceId;

  final void Function(String host, int port) onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onPing;
  final ValueChanged<bool> onTtsChanged;
  final ValueChanged<String> onVoiceChanged;

  @override
  State<ConnectionSheetView> createState() => _ConnectionSheetViewState();
}

class _Route {
  const _Route(this.icon, this.title, this.host, {this.note});

  final IconData icon;
  final String title;
  final String host;
  final String? note;
}

class _ConnectionSheetViewState extends State<ConnectionSheetView> {
  late final TextEditingController _host = TextEditingController(text: widget.initialHost);
  late final TextEditingController _port = TextEditingController(text: widget.initialPort.toString());

  static const _routes = [
    _Route(Icons.vpn_lock_rounded, 'Tailscale', CompanionServerConfig.defaultTailscaleIp, note: 'Recommended'),
    _Route(Icons.badge_outlined, 'Tailscale name', CompanionServerConfig.defaultMagicDns),
    _Route(Icons.wifi_rounded, 'Same Wi-Fi', CompanionServerConfig.defaultLanIp),
    _Route(Icons.usb_rounded, 'USB cable', CompanionServerConfig.defaultLocalhost),
  ];

  @override
  void initState() {
    super.initState();
    _host.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _host.removeListener(_changed);
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  bool get _connected => widget.status == CompanionConnectionStatus.connected;
  bool get _connecting => widget.status == CompanionConnectionStatus.connecting;
  bool get _failed => widget.status == CompanionConnectionStatus.error;

  void _connect() {
    FocusScope.of(context).unfocus();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? CompanionServerConfig.defaultPort;
    widget.onConnect(host.isNotEmpty ? host : CompanionServerConfig.defaultTailscaleIp, port);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        // Never taller than what is left above the keyboard.
        constraints: BoxConstraints(maxHeight: (media.size.height - media.viewInsets.bottom) * 0.94),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(color: const Color(0xFFE2D6C0), borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              _header(),
              const KitLabel('ROUTE'),
              _routeList(),
              const KitLabel('ADDRESS'),
              _addressCard(),
              const SizedBox(height: 14),
              _actions(),
              const KitLabel('VOICE'),
              _voiceCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final (label, color) = switch (widget.status) {
      CompanionConnectionStatus.connected => ('Live · ${widget.latencyMs ?? 0} ms', const Color(0xFF4F9D76)),
      CompanionConnectionStatus.connecting => ('Connecting', const Color(0xFFD69E2E)),
      CompanionConnectionStatus.error => ("Can't reach it", const Color(0xFFD2603A)),
      _ => ('Offline', kitMuted),
    };
    return Row(
      children: [
        const IconTile(icon: Icons.hub_outlined, color: kitCoral, size: 44),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: kitInk),
              ),
              Text(
                "Where Sol's server lives",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kitMuted),
              ),
            ],
          ),
        ),
        StatusPill(label, color: color),
      ],
    );
  }

  Widget _routeList() {
    final current = _host.text.trim();
    return KitCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < _routes.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 58, color: kitLine),
            _routeTile(_routes[i], selected: current == _routes[i].host),
          ],
        ],
      ),
    );
  }

  Widget _routeTile(_Route route, {required bool selected}) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${route.title}, ${route.host}',
      child: InkWell(
        key: ValueKey('route-${route.host}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          FocusScope.of(context).unfocus();
          _host.text = route.host;
          _port.text = CompanionServerConfig.defaultPort.toString();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              IconTile(icon: route.icon, color: selected ? kitCoral : kitMuted, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            route.title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kitInk),
                          ),
                        ),
                        if (route.note != null) ...[
                          const SizedBox(width: 8),
                          StatusPill(route.note!, color: kitCoral),
                        ],
                      ],
                    ),
                    Text(
                      route.host,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kitSoft),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? kitCoral : kitMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF9F5EC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: kitAmber, width: 1.6),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  Widget _addressCard() {
    return KitCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              key: const ValueKey('connection-host'),
              controller: _host,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: _field('Host or IP', CompanionServerConfig.defaultTailscaleIp),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              key: const ValueKey('connection-port'),
              controller: _port,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
              decoration: _field('Port', '${CompanionServerConfig.defaultPort}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    final ButtonStyle filled = FilledButton.styleFrom(
      backgroundColor: kitCoral,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KitCard(
              color: const Color(0xFFFFF1EC),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 20, color: Color(0xFFD2603A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.errorMessage ?? "Couldn't reach the server.",
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF9E4010)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_connected)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('connection-ping'),
                  onPressed: widget.onPing,
                  icon: const Icon(Icons.network_ping_rounded, size: 18),
                  label: const Text('Test ping'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kitInk,
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: Color(0xFFDDD2BE)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('connection-disconnect'),
                  onPressed: widget.onDisconnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEDE6D8),
                    foregroundColor: kitInk,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Disconnect'),
                ),
              ),
            ],
          )
        else
          FilledButton(
            key: const ValueKey('connection-connect'),
            onPressed: _connecting ? null : _connect,
            style: filled,
            child: _connecting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      ),
                      SizedBox(width: 10),
                      Text('Connecting'),
                    ],
                  )
                : Text(_failed ? 'Try again' : 'Connect'),
          ),
      ],
    );
  }

  Widget _voiceCard() {
    return KitCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: Icons.record_voice_over_rounded, color: kitAmber, size: 38),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Speak replies aloud',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kitInk),
                    ),
                    Text(
                      'New voices are coming.',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kitMuted),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('connection-tts'),
                value: widget.ttsEnabled,
                onChanged: widget.onTtsChanged,
              ),
            ],
          ),
          if (widget.ttsEnabled) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, name) in connectionVoices)
                  ChoiceChip(
                    key: ValueKey('voice-$id'),
                    label: Text(name),
                    selected: widget.voiceId == id,
                    showCheckmark: false,
                    selectedColor: const Color(0xFFFFE0D0),
                    backgroundColor: const Color(0xFFF7F2E7),
                    side: BorderSide(color: widget.voiceId == id ? const Color(0xFFFF9E70) : const Color(0xFFDDD2BE)),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: widget.voiceId == id ? const Color(0xFF9E4010) : kitInk,
                    ),
                    onSelected: (_) => widget.onVoiceChanged(id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
