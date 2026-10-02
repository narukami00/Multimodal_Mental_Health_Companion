import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../footprint/break_prompt_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import '../profile/profile_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'helps_tab.dart';
import 'insight_widgets.dart';
import 'mood_tab.dart';
import 'phone_tab.dart';

/// Insights: real reflections from what the person has shared and what their
/// phone has shown, in tabs. Nothing here is invented: a tab with no data says
/// what would fill it, and every statement describes and never diagnoses.
class InsightsPage extends StatefulWidget {
  const InsightsPage({
    required this.sessionController,
    this.suggestionController,
    this.phonePatterns,
    this.profileController,
    this.breakPrompts,
    this.momentsTab,
    this.clock,
    super.key,
  });

  final SessionController sessionController;

  /// Without it there is no "Helps" tab.
  final SuggestionController? suggestionController;

  /// With [profileController], gives the "Phone" tab.
  final PhonePatternsController? phonePatterns;
  final ProfileController? profileController;
  final BreakPromptController? breakPrompts;

  /// The "Moments" tab's content, when that feature is available.
  final Widget? momentsTab;
  final DateTime Function()? clock;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _Tab {
  const _Tab(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

class _InsightsPageState extends State<InsightsPage> {
  String _selected = 'mood';

  List<_Tab> get _tabs => [
    const _Tab('mood', 'Mood', Icons.wb_twilight_rounded),
    if (widget.suggestionController != null)
      const _Tab('helps', 'Helps', Icons.favorite_rounded),
    if (widget.phonePatterns != null && widget.profileController != null)
      const _Tab('phone', 'Phone', Icons.smartphone_rounded),
    if (widget.momentsTab != null)
      const _Tab('moments', 'Moments', Icons.auto_awesome_rounded),
  ];

  Widget _content(String id) => switch (id) {
    'helps' => HelpsTab(suggestionController: widget.suggestionController!),
    'phone' => PhoneTab(
      phonePatterns: widget.phonePatterns!,
      profileController: widget.profileController!,
      breakPrompts: widget.breakPrompts,
      clock: widget.clock,
    ),
    'moments' => widget.momentsTab!,
    _ => MoodTab(
      sessionController: widget.sessionController,
      phonePatterns: widget.phonePatterns,
      clock: widget.clock,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final selected = tabs.any((t) => t.id == _selected) ? _selected : tabs.first.id;

    return Scaffold(
      backgroundColor: SolaceColors.from(context).background,
      body: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned(
              top: -100,
              left: -60,
              child: _AmbientBlob(color: Color(0x38FFB534), size: 300),
            ),
            const Positioned(
              top: 80,
              right: -90,
              child: _AmbientBlob(color: Color(0x28FF7F50), size: 260),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: SingleChildScrollView(
                      // Room for the floating pill, which overlays the page.
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(context),
                          const SizedBox(height: 16),
                          _TabBar(
                            tabs: tabs,
                            selected: selected,
                            onSelected: (id) => setState(() => _selected = id),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOut,
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween(
                                  begin: const Offset(0, 0.02),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: KeyedSubtree(
                              key: ValueKey(selected),
                              child: _content(selected),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 24, 8, 4),
                            child: Text(
                              'Patterns are reflections of what you shared, never clinical conclusions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.65,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB9AB96),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PATTERNS OVER TIME',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFFD08018),
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Insights',
              style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
                color: insightInk,
              ),
            ),
          ],
        ),
      ),
      GestureDetector(
        onTap: () => _showAboutSheet(context),
        child: Semantics(
          button: true,
          label: 'How these reflections are made',
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xB8FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: insightLine),
            ),
            child: const Icon(Icons.info_outline_rounded, size: 19, color: insightSoft),
          ),
        ),
      ),
    ],
  );

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFDF7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0x293B2F26),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'How these reflections are made',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'They come only from what you chose to share: your check-ins and '
                'how you said you felt after trying things, plus phone patterns '
                'if you turned them on. Phone patterns stay on your device. There '
                'are no comparisons with anyone else.',
                style: TextStyle(
                  fontSize: 13.4,
                  height: 1.65,
                  fontWeight: FontWeight.w600,
                  color: insightSoft,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'They are gentle observations, never verdicts. If one does not '
                'ring true, set it aside. You know your week better than any '
                'pattern does.',
                style: TextStyle(
                  fontSize: 13.4,
                  height: 1.65,
                  fontWeight: FontWeight.w600,
                  color: insightSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tabs, required this.selected, required this.onSelected});

  final List<_Tab> tabs;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xB8FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: insightLine),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: Semantics(
                button: true,
                selected: tab.id == selected,
                label: tab.label,
                child: GestureDetector(
                  key: ValueKey('insights-tab-${tab.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(tab.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tab.id == selected ? const Color(0xFFFFB534) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 15,
                          color: tab.id == selected ? insightInk : insightMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: tab.id == selected ? insightInk : insightSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}
