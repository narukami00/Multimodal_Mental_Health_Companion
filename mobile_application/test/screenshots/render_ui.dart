import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/models/activity.dart';
import 'package:solace_mobile/core/models/suggestion_record.dart';
import 'package:solace_mobile/core/models/user_profile.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/data/contracts/activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_profile_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_safety_event_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_suggestion_repository.dart';
import 'package:solace_mobile/domain/recommendations/recommendation_engine.dart';
import 'package:solace_mobile/domain/home/home_card_priority.dart';
import 'package:solace_mobile/features/app_shell/home_suggestion_card.dart';
import 'package:solace_mobile/features/app_shell/today_page.dart';
import 'package:solace_mobile/features/companion/blob_simulation.dart';
import 'package:solace_mobile/features/companion/companion_blob.dart';
import 'package:solace_mobile/features/profile/profile_controller.dart';
import 'package:solace_mobile/features/profile/profile_page.dart';
import 'package:solace_mobile/features/rhythm/rhythm_detail_page.dart';
import 'package:solace_mobile/features/safety/safety_controller.dart';
import 'package:solace_mobile/features/sessions/session_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_card_surface.dart';
import 'package:solace_mobile/features/suggestions/suggestion_controller.dart';
import 'package:solace_mobile/features/suggestions/suggestion_page.dart';
import 'package:solace_mobile/main.dart';
import 'package:solace_mobile/providers/mock/mock_providers.dart';
import 'package:solace_mobile/providers/safety/keyword_safety_screener.dart';
import 'package:solace_mobile/data/repositories/asset_activity_library_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_onboarding_repository.dart';
import 'package:solace_mobile/data/repositories/in_memory_session_repository.dart';

/// Renders the screens to PNG files so they can actually be looked at.
///
/// Named without a _test suffix so the normal suite does not run it. Run it
/// deliberately, with --update-goldens to write the files:
///   flutter test test/screenshots/render_ui.dart --update-goldens
///
/// This exists because the UI was written for weeks without anyone looking at
/// it, and every review passed anyway. Tests do not tell you whether something
/// looks good.
const _phone = Size(390, 844);

/// Loads a real font. Without this the test environment renders every glyph as
/// a filled box, which makes any screenshot useless for judging.
Future<void> _loadFonts() async {
  const candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    'C:/Windows/Fonts/segoeuib.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  // The app theme asks for Nunito, which is not bundled, so on a device this
  // falls back to the platform font. Registering the system font under that
  // name is what makes the text legible here.
  final loader = FontLoader('Nunito');
  var loaded = 0;
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
    loaded++;
  }
  // ignore: avoid_print
  print('FONTS LOADED: $loaded');
  await loader.load();
}

/// Serves a fixed library so nothing waits on an asset read under fake async.
class _FixedLibrary implements ActivityLibraryRepository {
  const _FixedLibrary(this.activities);

  final List<Activity> activities;

  @override
  Future<List<Activity>> load() async => activities;
}

/// Renders a whole screen, rather than a single widget.
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: RepaintBoundary(key: const ValueKey('shot'), child: page),
    ),
  );
  await tester.pump();
}

Activity _activity({
  String id = 'walk',
  String title = 'Take a short easy walk',
  String description = 'Walk at a comfortable pace for a few minutes.',
  ActivityType type = ActivityType.movement,
}) {
  return Activity(
    id: id,
    title: title,
    description: description,
    type: type,
    effort: ActivityEffort.low,
    durationMinutes: 5,
    contexts: const [],
    targetStates: const [],
    review: ActivityReviewMetadata(
      status: ActivityReviewStatus.approved,
      evidenceTier: ActivityEvidenceTier.lifestyle,
      reviewerRole: 'test',
      reviewedAt: DateTime(2026, 1, 1),
    ),
  );
}

SuggestionCardChoice _choice({
  String title = 'Take a short easy walk',
  String description = 'Walk at a comfortable pace for a few minutes.',
  ActivityType type = ActivityType.movement,
}) {
  return SuggestionCardChoice(
    recommendation: Recommendation(
      activity: _activity(title: title, description: description, type: type),
      confidence: 0,
      isProactive: true,
      explanation: 'A gentle starter idea.',
      source: SuggestionSource.starter,
    ),
    context: const RecommendationContext(profileAgeDays: 3),
  );
}

/// Drives a [BlobSimulation] to a point in time, without a widget or a ticker.
///
/// The simulation takes wall-clock seconds and does its own fixed-step
/// subdivision, so feeding it a frame time is the whole job. Reused across
/// frames to stand in for a 60 Hz display.
class _BlobDriver {
  _BlobDriver(this.simulation);

  final BlobSimulation simulation;

  static const _frame = 1 / 60;

  /// Runs for [seconds] of wall clock at display rate.
  void run(double seconds) {
    final frames = (seconds / _frame).round();
    for (var i = 0; i < frames; i++) {
      simulation.advance(_frame);
    }
  }

  /// Runs until [when] holds, or gives up rather than hanging the suite.
  void runUntil(bool Function() when) {
    for (var i = 0; i < 60 * 30; i++) {
      simulation.advance(_frame);
      if (when()) return;
    }
    throw StateError('blob never reached the requested state');
  }
}

/// A [CompanionBlob] showing a simulation that has already been driven.
///
/// The real widget owns a ticker, and under the golden harness `animate: false`
/// stops it, so a live widget can never be caught in a transient state. This
/// paints the same painter over a pre-stepped simulation, which is what makes
/// the pop and the regrow reviewable at all.
class _FrozenBlob extends StatelessWidget {
  const _FrozenBlob({required this.sim, required this.diameter});

  final BlobSimulation sim;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter * BlobSimulation.inflateRadius * 1.15,
      height: diameter * BlobSimulation.inflateRadius * 1.15,
      child: CustomPaint(painter: _FrozenBlobPainter(sim)),
    );
  }
}

class _FrozenBlobPainter extends CustomPainter {
  _FrozenBlobPainter(this.sim);

  final BlobSimulation sim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // Duplicated from the real painter rather than shared, deliberately: making
    // it public just for the screenshot harness would widen the production API
    // to serve a test. If the real painter changes, this must change with it.
    final reach = sim.restRadius * sim.inflation;
    final ring = sim.points;
    if (ring.length >= 3 && sim.state != BlobState.bursting) {
      Path outline(double scale) {
        var cx = 0.0, cy = 0.0;
        for (final p in ring) {
          cx += p.dx;
          cy += p.dy;
        }
        cx /= ring.length;
        cy /= ring.length;
        final pts = <Offset>[
          for (final p in ring)
            Offset(cx + (p.dx - cx) * scale, cy + (p.dy - cy) * scale),
        ];
        final mid = List<Offset>.generate(
          pts.length,
          (i) => Offset(
            (pts[i].dx + pts[(i + 1) % pts.length].dx) / 2,
            (pts[i].dy + pts[(i + 1) % pts.length].dy) / 2,
          ),
        );
        final path = Path()..moveTo(mid.last.dx, mid.last.dy);
        for (var i = 0; i < pts.length; i++) {
          path.quadraticBezierTo(
            pts[i].dx,
            pts[i].dy,
            mid[i].dx,
            mid[i].dy,
          );
        }
        return path..close();
      }

      const amber = Color(0xFFFFB534);
      const coral = Color(0xFFFF7F50);
      const deep = Color(0xFFE86034);
      const cream = Color(0xFFFFF3D6);
      Offset light(double d) => const Offset(-0.42, -0.52) * d;

      final body = outline(1.0);
      canvas.drawCircle(
        Offset.zero,
        reach * 1.5,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, reach * 1.5, [
            amber.withValues(alpha: 0.22),
            coral.withValues(alpha: 0.10),
            coral.withValues(alpha: 0.0),
          ], const [0.0, 0.5, 1.0]),
      );

      Rect bounds() {
        var minX = 1e18, minY = 1e18, maxX = -1e18, maxY = -1e18;
        for (final p in ring) {
          if (p.dx < minX) minX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy > maxY) maxY = p.dy;
        }
        const slack = 4.0;
        return Rect.fromLTRB(
          minX - slack,
          minY - slack,
          maxX + slack,
          maxY + slack,
        );
      }

      canvas.saveLayer(bounds(), Paint());
      canvas.drawPath(
        body,
        Paint()
          ..shader = ui.Gradient.radial(light(reach * 0.30), reach * 1.15, [
            cream.withValues(alpha: 0.62),
            amber.withValues(alpha: 0.50),
            coral.withValues(alpha: 0.44),
            deep.withValues(alpha: 0.46),
          ], const [0.0, 0.38, 0.74, 1.0]),
      );
      canvas.drawPath(
        outline(0.80),
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(light(reach * 0.16), reach * 0.8, [
            cream.withValues(alpha: 0.34),
            amber.withValues(alpha: 0.26),
            amber.withValues(alpha: 0.0),
          ], const [0.0, 0.55, 1.0]),
      );
      canvas.drawPath(
        outline(0.46),
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(light(reach * 0.10), reach * 0.5, [
            coral.withValues(alpha: 0.30),
            deep.withValues(alpha: 0.20),
            deep.withValues(alpha: 0.0),
          ], const [0.0, 0.6, 1.0]),
      );
      canvas.restore();

      final charge = sim.chargeFraction;
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 + charge * 1.4
          ..color = Color.lerp(
            Colors.white.withValues(alpha: 0.55 + charge * 0.4),
            cream.withValues(alpha: 0.75 + charge * 0.25),
            charge,
          )!,
      );
      canvas.drawPath(
        outline(0.93),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = deep.withValues(alpha: 0.20),
      );
    }

    for (final d in sim.droplets) {
      if (d.opacity <= 0.002) continue;
      canvas.drawCircle(
        d.position,
        d.radius + 1.2,
        Paint()
          ..color = const Color(0xFFFFF3D6).withValues(alpha: 0.55 * d.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FrozenBlobPainter oldDelegate) =>
      oldDelegate.sim != sim;
}

/// Captures the widget to a PNG.
///
/// Uses the golden machinery rather than painting to an image directly: the
/// latter hung after one capture, and this is the path Flutter actually
/// supports. Run with --update-goldens to write the files.
Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(const ValueKey('shot')),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Color background = const Color(0xFFF7F1E7),
  double? height,
}) async {
  tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // A Scaffold, because without a Material ancestor the themed text style
      // never reaches the text and everything falls back to the test font.
      home: Scaffold(
        backgroundColor: background,
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _phone.width,
            height: height,
            // A ListView, like Home really is, so the card is laid out under
            // the same constraints it gets in the app.
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
              children: [
                RepaintBoundary(
                  key: const ValueKey('shot'),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('render the companion blob', (tester) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 30),
          CompanionBlob(diameter: 92, animate: false),
          SizedBox(height: 30),
          CompanionBlob(diameter: 140, animate: false),
        ],
      ),
    );
    await _capture(tester, 'companion_blob');
  });

  testWidgets('render the companion blob in every state', (tester) async {
    // The states are the point of this rewrite, and they cannot be reviewed from
    // the resting shape alone: a pop that is too fast, an inflate that stalls,
    // or a regrow that collapses all still look plausible in a static image of
    // the idle bubble. So each is driven to the state and captured.
    const diameter = 116.0;

    Future<void> capture(BlobState want, String name) async {
      final sim = BlobSimulation(restRadius: diameter / 2);
      final driver = _BlobDriver(sim);

      // Settle first, so a state is reached from a resting blob rather than from
      // the initial ring.
      driver.run(2.0);

      switch (want) {
        case BlobState.pulling:
          sim.grab(const Offset(diameter / 2, 0));
          driver.run(0.5);
          sim.dragTo(Offset(diameter / 2 + 42, 6));
          driver.run(0.5);
        case BlobState.charged:
          sim.grab(const Offset(diameter / 2, 0));
          sim.beginInflate();
          driver.run(1.0);
        case BlobState.bursting:
          sim.grab(const Offset(diameter / 2, 0));
          sim.beginInflate();
          driver.runUntil(() => sim.state == BlobState.bursting);
          driver.run(BlobSimulation.burstGap * 0.45);
        case BlobState.regrowing:
          sim.grab(const Offset(diameter / 2, 0));
          sim.beginInflate();
          driver.runUntil(() => sim.state == BlobState.regrowing);
          driver.run(0.30);
        case _:
          break;
      }

      await _pump(
        tester,
        _FrozenBlob(sim: sim, diameter: diameter),
      );
      await _capture(tester, name);
    }

    await capture(BlobState.idle, 'blob_state_idle');
    await capture(BlobState.pulling, 'blob_state_pulling');
    await capture(BlobState.charged, 'blob_state_inflated');
    await capture(BlobState.bursting, 'blob_state_bursting');
    await capture(BlobState.regrowing, 'blob_state_regrowing');
  });

  testWidgets('render the Home page around the blob', (tester) async {
    // TodayPage on its own rather than through SolaceApp.
    //
    // The whole-app capture cannot run here: the shell's ChatController reaches
    // for shared_preferences on startup, and that plugin has no implementation in
    // a test environment, so the frame throws before anything is drawn. This is
    // the one way to actually look at where the blob sits relative to the card,
    // which is the thing the layout arithmetic in today_page.dart is guessing at.
    tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('shot'),
            child: TodayPage(
              primaryCard: HomeCardType.checkIn,
              // Fixed, so the greeting and the date chip are stable across runs.
              currentTime: DateTime(2026, 10, 1, 19, 12),
            ),
          ),
        ),
      ),
    );
    // Fixed pumps rather than pumpAndSettle: the blob simulates continuously and
    // never settles, so waiting for stillness here would hang.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await _capture(tester, 'home_with_blob');
  });

  testWidgets('render the You tab', (tester) async {
    // The whole screen, at the phone size the shell uses.
    //
    // This page is nothing but grouping and hierarchy, so a picture of it is
    // worth more than any assertion about it: a list can pass every "the row is
    // present" check and still be arranged so the eye cannot find anything.
    final profileController = ProfileController(
      repository: InMemoryProfileRepository(),
    );
    await profileController.load();
    await profileController.saveIdentity(
      displayName: 'Maya',
      avatarPath: null,
    );

    final sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    await sessions.seedInitialSessions();

    final suggestions = SuggestionController(
      libraryRepository: _FixedLibrary([_activity()]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await suggestions.load();
    await suggestions.warmUp();

    tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ProfilePage(
            profileController: profileController,
            safetyController: SafetyController(
              screener: const KeywordSafetyScreener(),
              repository: InMemorySafetyEventRepository(),
            ),
            suggestionController: suggestions,
            sessionController: sessions,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await _capture(tester, 'you_tab');

    // And the bottom of it. The About group sits entirely below the fold, which
    // is the point of putting it last — and also the reason it would otherwise
    // never be looked at.
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -600),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await _capture(tester, 'you_tab_bottom');
  });

  testWidgets('render the suggestion card', (tester) async {
    await _pump(
      tester,
      HomeSuggestionCard(choice: _choice(), onAccept: (_) {}),
    );
    await _capture(tester, 'card_movement');
  });

  testWidgets('render a mindfulness card', (tester) async {
    await _pump(
      tester,
      HomeSuggestionCard(
        choice: _choice(
          title: 'Make a one-minute pause',
          description:
              'Set a gentle timer for one minute and notice what changes in your attention while you wait.',
          type: ActivityType.mindfulness,
        ),
        onAccept: (_) {},
      ),
    );
    await _capture(tester, 'card_mindfulness');
  });

  testWidgets('render a productivity card', (tester) async {
    await _pump(
      tester,
      HomeSuggestionCard(
        choice: _choice(
          title: 'Create a softer stopping point',
          description:
              'Choose where to pause a task and write one sentence that makes restarting easier later.',
          type: ActivityType.productivity,
        ),
        onAccept: (_) {},
      ),
    );
    await _capture(tester, 'card_productivity');
  });

  testWidgets('render the rating step', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _FixedLibrary([
        _activity(
          title: 'Create a softer stopping point',
          description:
              'Choose where to pause a task and write one sentence that makes restarting easier later.',
          type: ActivityType.productivity,
        ),
      ]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();
    final peeked = controller.peek(
      profile: const UserProfile(),
      context: const RecommendationContext(profileAgeDays: 3),
    )!;
    final record = await controller.commit(
      peeked,
      context: const RecommendationContext(profileAgeDays: 3),
    );

    await _pumpPage(
      tester,
      SuggestionPage(
        suggestionController: controller,
        profileController: ProfileController(
          repository: InMemoryProfileRepository(),
        ),
        safetyController: SafetyController(
          screener: const KeywordSafetyScreener(),
          repository: InMemorySafetyEventRepository(),
        ),
        seededRecordId: record.id,
      ),
    );
    await _capture(tester, 'page_rating');
  });

  testWidgets('render the decide step', (tester) async {
    final controller = SuggestionController(
      libraryRepository: _FixedLibrary([
        _activity(
          title: 'Create a softer stopping point',
          description:
              'Choose where to pause a task and write one sentence that makes restarting easier later.',
          type: ActivityType.productivity,
        ),
      ]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpPage(
      tester,
      SuggestionPage(
        suggestionController: controller,
        profileController: ProfileController(
          repository: InMemoryProfileRepository(),
        ),
        safetyController: SafetyController(
          screener: const KeywordSafetyScreener(),
          repository: InMemorySafetyEventRepository(),
        ),
      ),
    );
    // The page requests its suggestion asynchronously, so pump a few frames.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, 'page_decide');
  });

  testWidgets('render the whole Home screen', (tester) async {
    final sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    await sessions.seedInitialSessions();

    final controller = SuggestionController(
      libraryRepository: AssetActivityLibraryRepository(),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    final onboarding = InMemoryOnboardingRepository();
    await onboarding.complete();

    tester.view.physicalSize = Size(_phone.width * 3, _phone.height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: SolaceApp(
          onboardingRepository: onboarding,
          sessionController: sessions,
          suggestionController: controller,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, 'home_full');
  });

  testWidgets('render the rhythm detail page', (tester) async {
    final sessions = SessionController(
      repository: InMemorySessionRepository(),
      emotionAnalyzer: const MockEmotionAnalyzer(),
    );
    await sessions.load();
    await sessions.seedInitialSessions();

    final controller = SuggestionController(
      libraryRepository: _FixedLibrary([_activity()]),
      suggestionRepository: InMemorySuggestionRepository(),
    );
    await controller.load();
    await controller.warmUp();

    await _pumpPage(
      tester,
      RhythmDetailPage(
        sessionController: sessions,
        profileController: ProfileController(
          repository: InMemoryProfileRepository(),
        ),
        suggestionController: controller,
        libraryRepository: _FixedLibrary([_activity()]),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, 'rhythm_detail');
  });
}
