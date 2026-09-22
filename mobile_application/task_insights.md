# Task: Implement Screen 5 - Insights & Emotional Trends Page

## Goal
Implement `lib/features/insights/insights_page.dart` matching the visual design, typography, layout, and non-punitive tone of `html_ref/analytics.html`.
Wire this page into `lib/features/app_shell/app_shell.dart` under tab index 2 (`insights`).

## Strict Design & Layout Rules
1. **Zero Clipping / Responsive Viewport**:
   - Wrap the Scaffold body in `ClipRect` with `Positioned.fill` or `SingleChildScrollView`:
   ```dart
   Scaffold(
     backgroundColor: const Color(0xFFFEFCE8),
     body: ClipRect(
       child: Stack(
         clipBehavior: Clip.hardEdge,
         children: [
           // ambient radial glow blobs
           Positioned(top: -100, left: -60, child: _AmbientBlob(color: Color(0x38FFB534), size: 300)),
           Positioned(top: 80, right: -90, child: _AmbientBlob(color: Color(0x28FF7F50), size: 260)),
           Positioned.fill(
             child: SafeArea(
               child: Center(
                 child: ConstrainedBox(
                   constraints: const BoxConstraints(maxWidth: 360),
                   child: SingleChildScrollView(
                     padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                     child: Column( ... ),
                   ),
                 ),
               ),
             ),
           ),
         ],
       ),
     ),
   );
   ```
2. **Header Section**:
   - Eyebrow: `PATTERNS OVER TIME` (font size 11.5, bold 800, letterSpacing 1.2, color `#D08018`).
   - Title: `Insights` (font size 29, bold 800, color `#3A3125`).
   - Top right filter / share icon button (36x36 rounded 13px, subtle shadow).
   - Segmented toggle: `Week` / `Month` (interactive state toggling between 7-day and 30-day views, warm pill background `#FFF4DE`).
   - Range note: `Last 7 days · 6 check-ins`.

3. **Emotional Drift Chart Card**:
   - White card (`#FFFFFF`), radius 26, warm dual box shadow, border `0x143B2F26`.
   - Eyebrow `EMOTIONAL DRIFT` + state pill with glowing dot `Tender · Steadying`.
   - Title: `Mornings are easing up` (font 19, bold 800, color `#3A3125`).
   - Smooth curved spline line chart with gradient fill underneath (`Color(0x38FFB534)` to `Colors.transparent`).
   - Dotted grid lines with state zone labels (`CALM`, `STEADY`, `WOBBLY`).
   - Day dots (`Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, `Sun`), active pulse halo on latest day.
   - Interactive or prominent tooltip pill: `Tue` - `Steady · Tea walk`.
   - Summary sentence with bold keyword accents: `You moved from wobbly to steady 4 out of 5 days after stepping outside.`

4. **Sentence-Based Insight Noticings Cards**:
   - `NOTICINGS` section label with fading trailing line.
   - Amber card (`tint-amber`): Morning sunlight (`Stepping into morning light aligns with calmer check-ins later.`, meta: `MORNING CHECK-INS`, icon: `wb_sunny_rounded`).
   - Coral card (`tint-coral`): Work sync tension (`Short breathers before standups softened self-reported tension.`, meta: `MIDDAY VOICE`, icon: `air_rounded`).
   - Sage card (`tint-sage`): Evening wind-down (`Wind-down reflections had fewer high-arousal words this week.`, meta: `EVENING TEXT`, icon: `bedtime_rounded`).
   - Each card has expand/collapse chevron showing gentle reflection tips and a link chip (e.g. `Explore breathing practice`).

5. **Incongruence / Gentle Note Card**:
   - Warm amber-coral gradient container:
   - Header with spark icon + `GENTLE NOTICING`.
   - Body: `Words and voice carried different tones on Thursday.`
   - Gentle action buttons: `Explore this moment` (gradient pill button) and `Keep it as is` (subtle text button).

6. **Non-Clinical Safety Reassurance Footer**:
   - `Patterns are reflections of what you logged, never clinical conclusions.`

7. **Integration**:
   - In `lib/features/app_shell/app_shell.dart`, import `insights_page.dart` and render `InsightsPage(sessionController: widget.sessionController)` when `_selectedTab == 2`.
   - Run `flutter test` to guarantee all tests pass.
