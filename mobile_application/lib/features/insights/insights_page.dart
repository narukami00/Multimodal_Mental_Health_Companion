import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/solace_palette.dart';
import '../sessions/session_controller.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({required this.sessionController, super.key});

  final SessionController sessionController;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  static const _line = Color(0x143B2F26);

  bool _isMonth = false;
  final Set<int> _openNoticings = {};

  _RangeData get _range => _isMonth ? _month : _week;

  @override
  Widget build(BuildContext context) {
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 16),
                          _buildChartCard(),
                          _buildSectionLabel('NOTICINGS'),
                          for (var i = 0; i < _noticings.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildNoticing(i),
                            ),
                          _buildGentleNote(),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 22, 8, 4),
                            child: Text(
                              'Patterns are reflections of what you logged, never clinical conclusions.',
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

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                      color: _inkColor,
                    ),
                  ),
                ],
              ),
            ),
            _iconButton(context),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _SegmentedRange(
              isMonth: _isMonth,
              onChanged: (month) => setState(() => _isMonth = month),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _range.note,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.12,
                  color: _mutedColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAboutSheet(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xB8FFFFFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x47B0782A),
              blurRadius: 14,
              spreadRadius: -6,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: _inkSoftColor,
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    final range = _range;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(26)),
        border: Border.fromBorderSide(BorderSide(color: _line)),
        boxShadow: [
          BoxShadow(
            color: Color(0x4DB0782A),
            blurRadius: 26,
            spreadRadius: -12,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x12B0782A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            const Positioned(
              top: -60,
              right: -50,
              child: _AmbientBlob(color: Color(0x29FFB534), size: 190),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EMOTIONAL DRIFT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: _mutedColor,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Mornings are easing up',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.25,
                                height: 1.25,
                                color: _inkColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _StatePill(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _DriftChart(
                    days: range.days,
                    words: range.words,
                    values: range.values,
                    key: ValueKey(_isMonth),
                  ),
                  const SizedBox(height: 8),
                  CustomPaint(
                    size: const Size.fromHeight(1),
                    painter: const _DashedLinePainter(),
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 13.2,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                        color: _inkSoftColor,
                      ),
                      children: [
                        TextSpan(text: 'You moved from '),
                        TextSpan(
                          text: 'wobbly to steady',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _inkColor,
                          ),
                        ),
                        TextSpan(text: ' '),
                        TextSpan(
                          text: '4 out of 5 days',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _inkColor,
                          ),
                        ),
                        TextSpan(text: ' after stepping outside.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: _mutedColor,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x1F3B2F26), Color(0x003B2F26)],
                ),
              ),
              child: SizedBox(height: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticing(int index) {
    final item = _noticings[index];
    final open = _openNoticings.contains(index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (open) {
          _openNoticings.remove(index);
        } else {
          _openNoticings.add(index);
        }
      }),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4DB0782A),
              blurRadius: 26,
              spreadRadius: -12,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: Color(0x12B0782A),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: item.tint,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(item.icon, size: 21, color: item.tintColor),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.text,
                        style: const TextStyle(
                          fontSize: 14.6,
                          fontWeight: FontWeight.w700,
                          height: 1.42,
                          letterSpacing: -0.15,
                          color: _inkColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.meta,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.77,
                          color: _mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: open ? const Color(0xFFF0A020) : const Color(0xFFCBBEA9),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: open
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: 55),
                          child: Text(
                            item.tip,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.6,
                              color: _inkSoftColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Padding(
                          padding: const EdgeInsets.only(left: 55),
                          child: _LinkChip(
                            label: item.chipLabel,
                            snack: item.chipSnack,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGentleNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.2, -1),
          end: Alignment(0.2, 1),
          colors: [Color(0xFFFFFCF3), Color(0xFFFFEDE4)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x4DFFB534)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73B0782A),
            blurRadius: 22,
            spreadRadius: -14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: Color(0xFFD89A4C),
              ),
              const SizedBox(width: 9),
              const Text(
                'GENTLE NOTICING',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.27,
                  color: Color(0xFFC98A3C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Words and voice carried different tones on Thursday.',
            style: TextStyle(
              fontSize: 13.4,
              fontWeight: FontWeight.w600,
              height: 1.62,
              color: Color(0xFF6E5C48),
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _snack('Opening your moment from Thursday'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xCCFF7F50),
                        blurRadius: 14,
                        spreadRadius: -6,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Explore this moment',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _snack('Left exactly as it is'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(
                    'Keep it as is',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB6A48C),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF3B2F26),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFDF7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
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
                "They come only from what you've already shared — your check-ins and journal notes. No one else's data, no comparisons, nothing leaving your device.",
                style: TextStyle(
                  fontSize: 13.4,
                  height: 1.65,
                  fontWeight: FontWeight.w600,
                  color: _inkSoftColor,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Patterns are offered as gentle observations, never as verdicts. If one doesn't ring true, it's fine to set it aside. You know your week better than any pattern does.",
                style: TextStyle(
                  fontSize: 13.4,
                  height: 1.65,
                  fontWeight: FontWeight.w600,
                  color: _inkSoftColor,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xE6FF7F50),
                          blurRadius: 22,
                          spreadRadius: -10,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _inkColor = Color(0xFF3A3125);
const _inkSoftColor = Color(0xFF6C5E50);
const _mutedColor = Color(0xFFA69883);

class _RangeData {
  const _RangeData({
    required this.note,
    required this.days,
    required this.words,
    required this.values,
  });

  final String note;
  final List<String> days;
  final List<String> words;
  final List<double> values;
}

const _week = _RangeData(
  note: 'Last 7 days · 6 check-ins',
  days: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  words: [
    'Wobbly · Slow start',
    'Steady · Tea walk',
    'Wobbly · Short sleep',
    'Calm · Clear head',
    'Steady · Walk at lunch',
    'Calm · Slow morning',
    'Hopeful · Tea outside',
  ],
  values: [44.0, 64.0, 46.0, 74.0, 68.0, 84.0, 78.0],
);

const _month = _RangeData(
  note: 'Last 30 days · 6 check-ins',
  days: ['Aug 19', 'Aug 26', 'Sep 2', 'Sep 9', 'Today'],
  words: [
    'Wobbly · Heavy week',
    'Steady · Two walks',
    'Wobbly · Deadline',
    'Calm · Better sleep',
    'Steady · Tea walk',
  ],
  values: [46.0, 64.0, 50.0, 76.0, 70.0],
);

class _Noticing {
  const _Noticing({
    required this.icon,
    required this.tint,
    required this.tintColor,
    required this.text,
    required this.meta,
    required this.tip,
    required this.chipLabel,
    required this.chipSnack,
  });

  final IconData icon;
  final LinearGradient tint;
  final Color tintColor;
  final String text;
  final String meta;
  final String tip;
  final String chipLabel;
  final String chipSnack;
}

const _noticings = [
  _Noticing(
    icon: Icons.wb_sunny_rounded,
    tint: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF3DA), Color(0xFFFFE7C2)],
    ),
    tintColor: Color(0xFFE39418),
    text: 'Stepping into morning light aligns with calmer check-ins later.',
    meta: 'MORNING CHECK-INS',
    tip:
        "On several of the last seven days your first check-in landed before "
        'nine — and those afternoons felt noticeably lighter. Nothing to chase '
        'here; it may just be that naming the day early gives it somewhere to '
        'go.',
    chipLabel: 'Explore breathing practice',
    chipSnack: 'Opening your breathing practice',
  ),
  _Noticing(
    icon: Icons.air_rounded,
    tint: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFEDE4), Color(0xFFFFDDD0)],
    ),
    tintColor: Color(0xFFF0764A),
    text: 'Short breathers before standups softened self-reported tension.',
    meta: 'MIDDAY VOICE',
    tip:
        'On the days you paused for a breath or two, your voice settled faster '
        'than the days you pushed straight through. A short breather before '
        'the next sync is enough; there is nothing here to fix.',
    chipLabel: 'Try a two-minute reset',
    chipSnack: 'Opening a two-minute reset',
  ),
  _Noticing(
    icon: Icons.bedtime_rounded,
    tint: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF2F5DF), Color(0xFFE7EFD2)],
    ),
    tintColor: Color(0xFF8FA04A),
    text: 'Wind-down reflections had fewer high-arousal words this week.',
    meta: 'EVENING TEXT',
    tip:
        'Even two or three lines seemed to help the day settle. The heaviest '
        'evenings were the ones with an empty page beside them — worth '
        'remembering on the nights writing feels like too much.',
    chipLabel: 'Open evening reflection',
    chipSnack: "Opening tonight's reflection",
  ),
];

class _SegmentedRange extends StatelessWidget {
  const _SegmentedRange({required this.isMonth, required this.onChanged});

  final bool isMonth;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x38FFB534)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('Week', selected: !isMonth, onTap: () => onChanged(false)),
          _seg('Month', selected: isMonth, onTap: () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x73B0782A),
                    blurRadius: 8,
                    spreadRadius: -2,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.25,
            color: selected ? _inkColor : _inkSoftColor.withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4DE), Color(0xFFFFEDE4)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x47FFB534)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB534), Color(0xFFFF7F50)],
              ),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38FFB534),
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'Tender · Steadying',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFFC9722F),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.label, required this.snack});

  final String label;
  final String snack;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              snack,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            backgroundColor: const Color(0xFF3B2F26),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            duration: const Duration(seconds: 2),
          ),
        ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF4DE), Color(0xFFFFEDE4)],
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFCE7330),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 13,
              color: Color(0xFFCE7330),
            ),
          ],
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
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _DriftChart extends StatefulWidget {
  const _DriftChart({
    super.key,
    required this.days,
    required this.words,
    required this.values,
  });

  final List<String> days;
  final List<String> words;
  final List<double> values;

  @override
  State<_DriftChart> createState() => _DriftChartState();
}

class _DriftChartState extends State<_DriftChart>
    with SingleTickerProviderStateMixin {
  // ponytail: one-shot entrance pulse instead of the HTML's infinite halo —
  // repeating animations would hang every pumpAndSettle() test that builds
  // the shell's IndexedStack. Revert to repeat() if it matters visually.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected =
        widget.days.contains('Today') ? widget.days.indexOf('Today') : 1;
    _pulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _DriftChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.values, widget.values)) {
      _pulse.forward(from: 0);
      if (widget.days.contains('Today')) {
        _selected = widget.days.indexOf('Today');
      } else {
        _selected = 1;
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static const _dayStyle = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.76,
    color: Color(0xFFA69883),
  );
  static const _wordStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: Color(0xFF3A3125),
  );

  TextPainter _layout(String text, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    final sel = _selected.clamp(0, n - 1);
    final label = widget.days[sel];
    final word = widget.words[sel];
    final dayTp = _layout(label, _dayStyle);
    final wordTp = _layout(word, _wordStyle);
    final pillW = math.max(dayTp.width, wordTp.width) + 22;
    final pillH = dayTp.height + wordTp.height + 13;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final s = w / 348.0;
        final h = 196.0 * s;
        final px =
            (_ChartPainter.l + (_ChartPainter.r - _ChartPainter.l) * (n == 1 ? 0 : sel / (n - 1))) * s;
        final v = widget.values[sel];
        final py = (_ChartPainter.b -
                ((v - _ChartPainter.dMin) /
                    (_ChartPainter.dMax - _ChartPainter.dMin)) *
                    (_ChartPainter.b - _ChartPainter.t)) *
            s;
        final tipLeft = (px - pillW / 2).clamp(2.0, math.max(2.0, w - pillW - 2));
        final tipTop = math.max(0.0, 44 + py - pillH - 14);

        void selectAt(double dx) {
          final rel = dx / s;
          var best = 0;
          var bestDist = double.infinity;
          for (var i = 0; i < n; i++) {
            final xi = _ChartPainter.l +
                (_ChartPainter.r - _ChartPainter.l) * (n == 1 ? 0 : i / (n - 1));
            final d = (xi - rel).abs();
            if (d < bestDist) {
              bestDist = d;
              best = i;
            }
          }
          if (best != _selected && mounted) {
            setState(() => _selected = best);
          }
        }

        return SizedBox(
          height: h + 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => selectAt(details.localPosition.dx),
                  onHorizontalDragUpdate: (details) =>
                      selectAt(details.localPosition.dx),
                  child: SizedBox(
                    height: h,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => CustomPaint(
                        size: Size(w, h),
                        painter: _ChartPainter(
                          values: widget.values,
                          days: widget.days,
                          selected: sel,
                          pulse: _pulse.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: tipLeft.toDouble(),
                top: tipTop,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(11, 6, 11, 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x4DFFB534)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8C96641E),
                        blurRadius: 22,
                        spreadRadius: -10,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _dayStyle),
                      const SizedBox(height: 1),
                      Text(word, style: _wordStyle),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.values,
    required this.days,
    required this.selected,
    required this.pulse,
  });

  static const _vbW = 348.0;
  static const l = 46.0;
  static const r = 330.0;
  static const t = 20.0;
  static const b = 152.0;
  static const _lblY = 176.0;
  static const dMin = 35.0;
  static const dMax = 95.0;

  final List<double> values;
  final List<String> days;
  final int selected;
  final double pulse;

  List<Offset> _points(double s) {
    final n = values.length;
    return [
      for (var i = 0; i < n; i++)
        Offset(
          (l + (r - l) * (n == 1 ? 0 : i / (n - 1))) * s,
          (b - ((values[i] - dMin) / (dMax - dMin)) * (b - t)) * s,
        ),
    ];
  }

  static Path _smooth(List<Offset> p, double k) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    if (p.length < 2) return path;
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = i == 0 ? p[i] : p[i - 1];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = i + 2 < p.length ? p[i + 2] : p2;
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6 * k,
        p1.dy + (p2.dy - p0.dy) / 6 * k,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6 * k,
        p2.dy - (p3.dy - p1.dy) / 6 * k,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _text(
    Canvas canvas,
    String text,
    double x,
    double top,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, top));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _vbW;
    final pts = _points(s);

    const zoneWords = ['CALM', 'STEADY', 'WOBBLY'];
    const zoneYs = [35.0, 86.0, 137.0];
    final gridPaint = Paint()
      ..color = const Color(0x173B2F26)
      ..strokeWidth = s;
    for (var i = 0; i < zoneYs.length; i++) {
      final y = zoneYs[i] * s;
      var x = l * s;
      while (x < r * s) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 2 * s, r * s), y), gridPaint);
        x += 7 * s;
      }
      _text(
        canvas,
        zoneWords[i],
        4 * s,
        (zoneYs[i] - 4.6) * s,
        const TextStyle(
          fontSize: 8.6,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.77,
          color: Color(0xFFBCAF9C),
        ),
      );
    }

    final line = _smooth(pts, 0.86);

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * s
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x66FFAE4A)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 6 * s),
    );

    final area = Path.from(line)
      ..lineTo(pts.last.dx, (b + 4) * s)
      ..lineTo(pts.first.dx, (b + 4) * s)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, t * s),
          Offset(0, (b + 4) * s),
          [const Color(0x38FFB534), Colors.transparent],
        ),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          pts.first,
          pts.last,
          const [Color(0xFFFFC766), Color(0xFFFFA245), Color(0xFFFF7F50)],
          const [0.0, 0.5, 1.0],
        ),
    );

    final last = pts.last;
    canvas.drawCircle(last, 7 * s, Paint()..color = const Color(0x59FF7F50));
    if (pulse < 1) {
      final e = Curves.easeOut.transform(pulse);
      final opacity =
          0.5 * (1 - Curves.easeOut.transform((pulse / 0.7).clamp(0.0, 1.0)));
      if (opacity > 0.01) {
        canvas.drawCircle(
          last,
          7 * s * (0.55 + 1.2 * e),
          Paint()..color = Color.fromRGBO(255, 127, 80, opacity),
        );
      }
    }

    for (var i = 0; i < pts.length; i++) {
      final isLast = i == pts.length - 1;
      final isSel = i == selected;
      final radius = (isLast ? 5.2 : isSel ? 6.4 : 3.6) * s;
      canvas.drawCircle(pts[i], radius, Paint()..color = Colors.white);
      canvas.drawCircle(
        pts[i],
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ((isLast || isSel) ? 3.0 : 2.4) * s
          ..color = Color(isLast || isSel ? 0xFFFF7F50 : 0xFFFFA245),
      );
    }

    for (var i = 0; i < pts.length; i++) {
      final isLast = i == pts.length - 1;
      _text(
        canvas,
        days[i],
        pts[i].dx - 20 * s,
        (_lblY - 9) * s,
        TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isLast ? const Color(0xFFE08A32) : const Color(0xFFB0A291),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.pulse != pulse ||
        !listEquals(oldDelegate.values, values) ||
        !listEquals(oldDelegate.days, days);
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x1A3B2F26)
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 2, size.width), size.height / 2),
        paint,
      );
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) => false;
}
