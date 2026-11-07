import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/constants/moods.dart';
import '../../core/models/daily_features.dart';
import '../../core/theme/solace_palette.dart';
import '../../core/widgets/visual_kit.dart';
import '../../domain/export/image_pdf.dart';
import '../../domain/export/therapist_summary.dart';
import '../../domain/goals/goals.dart';
import '../../services/data_ownership.dart';
import '../footprint/phone_patterns_controller.dart';
import '../insights/mood_tab.dart' show moodColors;
import '../sessions/session_controller.dart';
import '../suggestions/suggestion_controller.dart';
import 'profile_controller.dart';

const _ink = Color(0xFF3A3125);
const _soft = Color(0xFF6E6252);
const _muted = Color(0xFFA69883);
const _rule = Color(0xFFE8DCC6);
const _amber = Color(0xFFFFB534);

/// The page size the summary is laid out for (A4 in points) and how sharply it is drawn for the PDF.
const summaryPageSize = Size(595, 842);
const _pdfScale = 2.0;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _minutes(int m) => describeGoalValue(GoalMeasure.screenTime, m);

/// Draws the summary onto [canvas] as one page. Pure drawing: the same summary always gives the same page.
void paintTherapistSummary(Canvas canvas, Size size, TherapistSummary s, {DateTime? madeOn}) {
  const margin = 40.0;
  final width = size.width - margin * 2;
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  var y = 0.0;

  double text(
    String value, {
    double x = margin,
    double? maxWidth,
    double fontSize = 11.5,
    FontWeight weight = FontWeight.w500,
    Color color = _soft,
    double height = 1.35,
    double letterSpacing = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color, height: height, letterSpacing: letterSpacing),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? width);
    painter.paint(canvas, Offset(x, y));
    return painter.height;
  }

  void heading(String value) {
    y += 16;
    canvas.drawLine(Offset(margin, y), Offset(size.width - margin, y), Paint()..color = _rule..strokeWidth = 1);
    y += 9;
    y += text(value, fontSize: 9.5, weight: FontWeight.w800, color: _muted, letterSpacing: 1.6) + 6;
  }

  // Header.
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 6), Paint()..color = _amber);
  y = 30;
  y += text('SOLACE', fontSize: 10, weight: FontWeight.w800, color: _muted, letterSpacing: 2.4) + 4;
  y += text('A summary of my last ${s.days} days', fontSize: 25, weight: FontWeight.w800, color: _ink, height: 1.15) + 4;
  y += text(
    '${_date(s.from)} to ${_date(s.to)}${s.name == null ? '' : '   ·   ${s.name}'}',
    fontSize: 12.5,
    weight: FontWeight.w700,
    color: _soft,
  );
  y += 4;
  y += text(
    'Made by me, from my own check-ins and from what my phone noticed. It describes; it does not diagnose or advise.',
    fontSize: 10.5,
    color: _muted,
  );

  heading('THE PERIOD');
  y += text(
    s.entries == 0
        ? 'No check-ins in this period.'
        : 'I checked in on ${s.activeDays} of ${s.days} days, ${s.entries} ${s.entries == 1 ? 'entry' : 'entries'} in all'
              '${s.voiceOrVideo > 0 ? ' (${s.voiceOrVideo} by voice or video)' : ''}.',
    fontSize: 13,
    weight: FontWeight.w600,
    color: _ink,
  );

  heading('HOW I FELT');
  if (s.moods.isEmpty) {
    y += text('No mood words in this period.', fontSize: 12.5, color: _soft);
  } else {
    final top = s.moods.first.value;
    for (final entry in s.moods.take(5)) {
      final internal = Moods.values.firstWhere((m) => Moods.display(m) == entry.key, orElse: () => 'Quiet');
      text(entry.key, fontSize: 12, weight: FontWeight.w700, color: _ink);
      final barLeft = margin + 78;
      final barMax = width - 78 - 34;
      final barW = math.max(6.0, barMax * (entry.value / top));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(barLeft, y + 2, barW, 11), const Radius.circular(6)),
        Paint()..color = moodColors[internal] ?? const Color(0xFFB4ADD6),
      );
      text('${entry.value}', x: barLeft + barMax + 8, maxWidth: 30, fontSize: 12, weight: FontWeight.w700, color: _soft);
      y += 20;
    }
  }

  heading('WHAT I TRIED');
  y += text(
    s.ideasTried == 0
        ? 'No small ideas tried in this period.'
        : 'I tried ${s.ideasTried} small ${s.ideasTried == 1 ? 'idea' : 'ideas'}'
              '${s.ideasLifted > 0 ? ', and felt lighter afterwards on ${s.ideasLifted}.' : '.'}',
    fontSize: 12.5,
    color: _ink,
    weight: FontWeight.w600,
  );

  final phone = s.phone;
  if (phone != null) {
    heading('MY PHONE');
    final cells = <(String, String)>[
      if (phone.typicalScreenMinutes != null) ('Screen time', _minutes(phone.typicalScreenMinutes!)),
      if (phone.typicalPickups != null) ('Pickups', '${phone.typicalPickups}'),
      if (phone.typicalLateNightMinutes != null) ('Late-night screen', _minutes(phone.typicalLateNightMinutes!)),
      if (phone.typicalFirstPickupMinute != null)
        ('First pickup', describeGoalValue(GoalMeasure.firstPickup, phone.typicalFirstPickupMinute!)),
    ];
    if (cells.isNotEmpty) {
      final cellW = width / cells.length;
      final top = y;
      var tallest = 0.0;
      for (var i = 0; i < cells.length; i++) {
        final x = margin + cellW * i;
        y = top;
        final h1 = text(cells[i].$2, x: x, maxWidth: cellW - 8, fontSize: 17, weight: FontWeight.w800, color: _ink);
        y = top + h1;
        final h2 = text(cells[i].$1, x: x, maxWidth: cellW - 8, fontSize: 10.5, color: _muted);
        tallest = math.max(tallest, h1 + h2);
      }
      y = top + tallest + 4;
    }
    y += text(
      'A typical day over ${phone.daysRead} ${phone.daysRead == 1 ? 'day' : 'days'} read on this phone. Estimates, kept on the phone.',
      fontSize: 10.5,
      color: _muted,
    );
  }

  if (s.goals.isNotEmpty) {
    heading('MY GOALS');
    for (final g in s.goals) {
      final result = g.judged == 0 ? 'not looked at yet' : 'met on ${g.met} of ${g.judged} ${g.judged == 1 ? 'day' : 'days'}';
      y += text('${g.title}: ${g.target.toLowerCase()}, $result.', fontSize: 12, color: _ink, weight: FontWeight.w600) + 3;
    }
  }

  if (s.words.isNotEmpty) {
    heading('IN MY OWN WORDS');
    for (final w in s.words) {
      if (y > size.height - 120) break;
      y += text(_date(w.day), fontSize: 9.5, weight: FontWeight.w800, color: _muted, letterSpacing: 0.6);
      y += text(w.text, fontSize: 11.5, color: _ink) + 7;
    }
  }

  // Footer.
  final footerY = size.height - 44;
  canvas.drawLine(Offset(margin, footerY - 8), Offset(size.width - margin, footerY - 8), Paint()..color = _rule..strokeWidth = 1);
  y = footerY;
  text(
    'Mood words are the ones I chose, or a model\'s reading of my own words. Phone numbers are estimates. '
    'Solace is a reflection space, not a medical or clinical provider.   Made ${_date(madeOn ?? DateTime.now())}.',
    fontSize: 8.5,
    color: _muted,
    height: 1.3,
  );
}

/// The page as a PDF, drawn sharply enough to print.
Future<Uint8List> renderSummaryPdf(TherapistSummary summary, {DateTime? madeOn}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(_pdfScale);
  paintTherapistSummary(canvas, summaryPageSize, summary, madeOn: madeOn);
  final w = (summaryPageSize.width * _pdfScale).round();
  final h = (summaryPageSize.height * _pdfScale).round();
  final image = await recorder.endRecording().toImage(w, h);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  final rgb = Uint8List(w * h * 3);
  final src = rgba.buffer.asUint8List();
  for (var i = 0, j = 0; i < src.length; i += 4, j += 3) {
    rgb[j] = src[i];
    rgb[j + 1] = src[i + 1];
    rgb[j + 2] = src[i + 2];
  }
  return imagePdf(rgb: rgb, width: w, height: h);
}

class _SummaryPainter extends CustomPainter {
  const _SummaryPainter(this.summary);
  final TherapistSummary summary;

  @override
  void paint(Canvas canvas, Size size) {
    // The page is laid out for a fixed size, so the preview scales it to fit the card.
    canvas.scale(size.width / summaryPageSize.width);
    paintTherapistSummary(canvas, summaryPageSize, summary);
  }

  @override
  bool shouldRepaint(_SummaryPainter old) => true;
}

/// "Summary for my therapist": pick a period, decide whether short pieces of your own entries are included (they are not
/// unless you say so), look at the page, and save it as a PDF. It leaves the phone only if you share the file.
class TherapistSummaryPage extends StatefulWidget {
  const TherapistSummaryPage({
    required this.sessionController,
    required this.suggestionController,
    required this.profileController,
    this.phonePatterns,
    this.files,
    this.clock,
    super.key,
  });

  final SessionController sessionController;
  final SuggestionController suggestionController;
  final ProfileController profileController;
  final PhonePatternsController? phonePatterns;

  /// Injectable (tests); the app uses the system file picker.
  final BackupFiles? files;
  final DateTime Function()? clock;

  @override
  State<TherapistSummaryPage> createState() => _TherapistSummaryPageState();
}

class _TherapistSummaryPageState extends State<TherapistSummaryPage> {
  int _days = 30;
  bool _words = false;
  bool _saving = false;
  List<DailyFeatures> _rows = const [];

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.phonePatterns?.storedDays().then((rows) {
      if (mounted) setState(() => _rows = rows);
    });
  }

  TherapistSummary get _summary => buildTherapistSummary(
    sessions: widget.sessionController.sessions,
    ideas: widget.suggestionController.history,
    phoneRows: _rows,
    goals: widget.phonePatterns?.goals?.goals ?? const [],
    goalDays: widget.phonePatterns?.goals?.days ?? const [],
    now: _now,
    days: _days,
    name: widget.profileController.profile.displayName,
    includeWords: _words,
  );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final pdf = await renderSummaryPdf(_summary, madeOn: _now);
      final d = _now;
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'solace-summary-${d.year}-${two(d.month)}-${two(d.day)}.pdf';
      final saved = await (widget.files ?? DataOwnership.instance.files).save(name, pdf);
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Your summary is saved.'), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SolaceColors.from(context);
    final summary = _summary;
    return Scaffold(
      backgroundColor: colors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const PageHero(
            scene: HeroScene.privacy,
            title: 'Summary for my therapist',
            subtitle: 'One page, made from your own entries.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KitLabel('HOW FAR BACK'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in const [7, 30, 90])
                      ChoiceChip(
                        key: ValueKey('summary-days-$d'),
                        label: Text('$d days'),
                        selected: _days == d,
                        onSelected: (_) => setState(() => _days = d),
                      ),
                  ],
                ),
                const KitLabel('WHAT IS ON IT'),
                KitCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                  child: SwitchListTile(
                    key: const ValueKey('summary-words'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Short pieces of my own entries', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    subtitle: const Text(
                      'Off unless you turn it on. Otherwise only counts and mood words.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                    value: _words,
                    onChanged: (v) => setState(() => _words = v),
                  ),
                ),
                const KitLabel('THE PAGE'),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kitLine),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  child: AspectRatio(
                    aspectRatio: summaryPageSize.width / summaryPageSize.height,
                    child: CustomPaint(key: const ValueKey('summary-page'), painter: _SummaryPainter(summary)),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('summary-save'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(_saving ? 'Saving…' : 'Save as PDF'),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                    'Nothing is sent anywhere. The file is saved where you choose, and it is yours to share or not.',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.5, color: kitMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
