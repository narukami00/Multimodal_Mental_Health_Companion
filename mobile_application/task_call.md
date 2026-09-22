# Task: Implement Screen 8 - Voice/Video Call Session Interface

## Goal
Implement `lib/features/call/call_page.dart` matching the visual design, typography, layout, and non-punitive tone of `html_ref/call.html`.

## Strict Design & Animation Rules
1. **Fullscreen Ambient Immersion**:
   - Wrap body in `ClipRect` with `Stack` constrained within `Center(ConstrainedBox(maxWidth: 392))`.
   - Background: Radial gradients with deep amber and coral tones (`radial-gradient(120% 70% at 50% 0%, #FFF7DE 0%, #FEFCE8 42%, #FDF6E4 72%, #FBF1DC 100%)`).

2. **Top Header**:
   - Back / Minimize chevron button (40x40, rounded 14px, subtle glass effect).
   - Session title: `Voice reflection` (font 16, bold 800, color `#4A3B2A`).
   - Live timer: `03:24` (font 12.5, bold 600, color `#8E7E6A`).
   - Safety badge / help button at top right.

3. **Central Breathing Orb**:
   - Stateful widget with `SingleTickerProviderStateMixin` and `AnimationController(duration: Duration(milliseconds: 6400))`.
   - Concentric glowing ripples that gently pulse.
   - Core orb: Multi-stop warm radial gradient (`#FFE3A6` -> `#FFB534` -> `#FF9A5C` -> `#FF7F50`) with warm shadow.
   - Subtitle below orb:
     `"Take your time. Silence is welcome here."` (font 14.5, font-weight 600, color `#6E5D49`).

4. **Bottom Control Dock**:
   - Glassmorphic / rounded card dock:
     - Mute button (toggle mic with active/muted state)
     - Audio output toggle (speaker / earpiece)
     - Camera toggle (audio to video mode)
     - End call button: Coral circle (54x54, gradient `#FF7F50` -> `#F06030`, white call-end icon). Tapping pops or saves reflection.

5. **Route Hook**:
   - Support `?route=call` in `lib/features/onboarding/onboarding_gate.dart`.
   - Verify all tests pass with `flutter test`.
