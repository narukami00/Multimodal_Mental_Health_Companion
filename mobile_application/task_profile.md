# Task: Implement Screen 6 - Profile & Settings Page

## Goal
Implement `lib/features/profile/profile_page.dart` matching the visual design, typography, layout, and non-punitive tone of `html_ref/profile_settings.html`.
Wire this page into `lib/features/app_shell/app_shell.dart` under tab index 3 (`profile`).

## Strict Design & Layout Rules
1. **Zero Clipping / Responsive Viewport**:
   - Wrap the Scaffold body in `ClipRect` with `SingleChildScrollView` within `Center(ConstrainedBox(maxWidth: 360))` to guarantee zero horizontal overflow on mobile viewports.
   - Background: Warm cream `#FEFCE8` with ambient radial glows.

2. **Top Header**:
   - Brandmark: Logo dotmark (amber-to-coral rounded 7px) + text `SOLACE` (font 12.5, bold 800, letterSpacing 1.4, color `#B9A98C`).
   - Action icon button (38x38, radius 13, border `#F2ECDD`, subtle shadow).

3. **Profile Header**:
   - Gradient avatar ring (74x74, radius 26, amber-coral gradient `#FFD88A` -> `#FFB534` -> `#FF9A6A`) with presence dot (`#8DCB8A` green with white ring).
   - User name: `Maya Lin` (or from `widget.profileController.profile.name` if present).
   - Subtitle: `Member since September 2026`.

4. **Gentle Rhythm Card (Non-Punitive Streak)**:
   - Container with warm gradient `#FFFDF6` -> `#FFFAEE`, radius 22, border `#F6EFD9`.
   - Amber leaf icon badge (38x38).
   - Title: `4-day rhythm` (bold 14, color `#4A4133`).
   - Subhead: `Showing up when it feels right · 2 rest days`.
   - 7 day dots representing the week (amber for checked in, coral for today, soft beige for rest).

5. **Section: YOUR SPACE**:
   - Section label: `YOUR SPACE` (uppercase, bold 11.5, color `#BCAC8E`).
   - White rounded card (radius 26, subtle shadow) with menu rows separated by divider lines:
     - Row 1: `Baseline reflections` (Icon: `assignment_outlined`), subtitle: `PHQ-9 & GAD-7 baseline assessment`, trailing badge: `Completed` or score range. Tapping navigates to `BaselineQuizPage`.
     - Row 2: `Check-in preferences` (Icon: `tune_rounded`), subtitle: `Modality default, gentle notifications`.
     - Row 3: `Safety & support catalog` (Icon: `health_and_safety_outlined`), subtitle: `Emergency contacts & crisis lines`. Tapping navigates to `SupportResourcesPage`.

6. **Section: PRIVACY & STORAGE**:
   - Section label: `PRIVACY & DATA`.
   - White rounded card with menu rows:
     - Row 1: `Export reflections` (Icon: `file_download_outlined`), subtitle: `Download your notes & entries`.
     - Row 2: `On-device encryption` (Icon: `lock_outline_rounded`), subtitle: `Encrypted locally, zero third-party telemetry`, trailing green badge `Active`.

7. **Crisis Support Action Card**:
   - Warm coral card (`#FFF4EE` -> `#FFEEE5`), border `#FFDAC8`, radius 26, left vertical coral accent bar.
   - Tile icon: `support_agent_rounded` in `#FFE4D6`.
   - Headline: `Need human care right now?` (bold 15.4, color `#B4522C`).
   - Subhead: `Free, confidential crisis lines available 24/7.`
   - Tapping pushes `SupportResourcesPage`.

8. **Footer**:
   - `Solace is a reflection space, not a medical or clinical provider.`
   - App version: `Solace v0.1.0 · Local-first & Private`.

9. **Integration & Test Pass**:
   - In `lib/features/app_shell/app_shell.dart`, import `profile_page.dart` and render `ProfilePage(...)` when `_selectedTab == 3`.
   - Ensure all `flutter test` tests pass!
