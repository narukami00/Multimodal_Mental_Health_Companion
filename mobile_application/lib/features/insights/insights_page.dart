import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../../domain/capacity/mood_trend.dart';
import '../footprint/break_prompt_controller.dart';
import '../footprint/phone_patterns_controller.dart';
import '../profile/profile_controller.dart';
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'helps_tab.dart';
import 'insight_widgets.dart';
import 'mood_tab.dart';
import 'phone_tab.dart';
import 'weeks_tab.dart';

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
    this.ideaActions,
    this.clock,
    this.tabRequest,
    super.key,
  });

  /// Lets something outside (the Today recap card) ask for a tab by id.
  final ValueNotifier<String?>? tabRequest;

  final SessionController sessionController;

  /// Without it there is no "Helps" tab.
  final SuggestionController? suggestionController;

  /// With [profileController], gives the "Phone" tab.
  final PhonePatternsController? phonePatterns;
  final ProfileController? profileController;
  final BreakPromptController? breakPrompts;

  /// The "Moments" tab's content, when that feature is available.
  final Widget? momentsTab;

  /// What the Helps tab's "Want to try something?" card does. Without it the card is not shown.
  final IdeaActions? ideaActions;
  final DateTime Function()? clock;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _Tab {
  const _Tab(this.id, this.label, this.icon, this.tint, this.accent);
  final String id;
  final String label;
  final IconData icon;
  final Color tint;
  final Color accent;
}

class _InsightsPageState extends State<InsightsPage> {
  String _selected = 'mood';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _selected = widget.tabRequest?.value ?? _selected;
    widget.tabRequest?.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    widget.tabRequest?.removeListener(_onTabRequest);
    _scroll.dispose();
    super.dispose();
  }

  void _onTabRequest() {
    final id = widget.tabRequest?.value;
    if (id != null && _tabs.any((t) => t.id == id)) _select(id);
  }

  void _select(String id) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (_selected != id) setState(() => _selected = id);
  }

  List<_Tab> get _tabs => [
    const _Tab(
      'mood',
      'Mood',
      Icons.wb_twilight_rounded,
      Color(0xFFFFE8DA),
      Color(0xFF9A4E2C),
    ),
    const _Tab(
      'weeks',
      'Weeks',
      Icons.calendar_view_week_rounded,
      Color(0xFFEAE4FA),
      Color(0xFF62518A),
    ),
    if (widget.suggestionController != null)
      const _Tab(
        'helps',
        'Helps',
        Icons.favorite_rounded,
        Color(0xFFE3F0DE),
        Color(0xFF477450),
      ),
    if (widget.phonePatterns != null && widget.profileController != null)
      const _Tab(
        'phone',
        'Phone',
        Icons.smartphone_rounded,
        Color(0xFFE1ECF9),
        Color(0xFF415E8F),
      ),
    if (widget.momentsTab != null)
      const _Tab(
        'moments',
        'Moments',
        Icons.auto_awesome_rounded,
        Color(0xFFE8E5FC),
        Color(0xFF57558C),
      ),
  ];

  Widget _content(String id) => switch (id) {
    'helps' => HelpsTab(
      suggestionController: widget.suggestionController!,
      ideaActions: widget.ideaActions,
      moodScores: dailyMoodScores(
        sessions: widget.sessionController.sessions,
        now: (widget.clock ?? DateTime.now)(),
        days: 7,
      ),
      clock: widget.clock,
    ),
    'phone' => PhoneTab(
      phonePatterns: widget.phonePatterns!,
      profileController: widget.profileController!,
      breakPrompts: widget.breakPrompts,
      clock: widget.clock,
    ),
    'weeks' => WeeksTab(
      sessionController: widget.sessionController,
      suggestionController: widget.suggestionController,
      goals: widget.phonePatterns?.goals,
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
    final current = tabs.firstWhere(
      (tab) => tab.id == _selected,
      orElse: () => tabs.first,
    );
    final selected = current.id;

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
                child: SingleChildScrollView(
                  controller: _scroll,
                  // Room for the floating pill, which overlays the page.
                  // Horizontal inset matches the Today page so cards line up
                  // across the app's pages.
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context),
                      const SizedBox(height: 16),
                      _SectionSwitcher(
                        tabs: tabs,
                        selected: current,
                        onSelected: _select,
                      ),
                      const SizedBox(height: 16),
                      // The outgoing tab is laid over the top of the new one and takes no space, so nothing
                      // is ever centred inside a taller neighbour (that made the content sit low and then
                      // jump up). The height eases to the new tab's, and the rise is a few pixels, not a
                      // fraction of the tab's height.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              for (final old in previous)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(child: old),
                                ),
                              if (current != null) current,
                            ],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: AnimatedBuilder(
                                  animation: animation,
                                  builder: (context, child) =>
                                      Transform.translate(
                                        offset: Offset(
                                          0,
                                          (1 - animation.value) * 8,
                                        ),
                                        child: child,
                                      ),
                                  child: child,
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ValueKey(selected),
                            child: _content(selected),
                          ),
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
            child: const Icon(
              Icons.info_outline_rounded,
              size: 19,
              color: insightSoft,
            ),
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

class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_Tab> tabs;
  final _Tab selected;
  final ValueChanged<String> onSelected;

  Widget _icon(_Tab tab) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: tab.tint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(tab.icon, color: tab.accent, size: 20),
  );

  Future<void> _open(BuildContext context) async {
    final palette = SolaceColors.from(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.surface,
      constraints: const BoxConstraints(maxWidth: 520),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Insights sections',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close sections',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tab in tabs)
                      Semantics(
                        selected: tab.id == selected.id,
                        child: ListTile(
                          key: ValueKey('insights-tab-${tab.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          minTileHeight: 56,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: _icon(tab),
                          title: Text(
                            tab.label,
                            style: TextStyle(
                              color: palette.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          selected: tab.id == selected.id,
                          selectedTileColor: palette.amber.withValues(
                            alpha: 0.16,
                          ),
                          trailing: tab.id == selected.id
                              ? Icon(Icons.check_rounded, color: tab.accent)
                              : null,
                          onTap: () => Navigator.of(context).pop(tab.id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice != null && context.mounted) onSelected(choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SolaceColors.from(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: insightLine),
    );
    return Material(
      color: palette.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('insights-section-switcher'),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _icon(selected),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Switch section',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: palette.mutedInk,
                      ),
                    ),
                    Text(
                      selected.label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: palette.mutedInk),
            ],
          ),
        ),
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
