# Task: Implement Screen 7 - Sol Companion Chat Interface

## Goal
Implement `lib/features/chat/chat_page.dart` matching the visual design, typography, layout, and non-punitive tone of `html_ref/chat_flow.html`.

## Strict Design & Safety Rules
1. **Zero Clipping / Responsive Viewport**:
   - Wrap body in `ClipRect` with `Stack` or `Column` within `Center(ConstrainedBox(maxWidth: 360))` to guarantee zero horizontal overflow.
   - Background: Warm cream `#FEFCE8` with ambient warm radial gradients.

2. **Top Header**:
   - Back button (44x44, radius 16, warm cream).
   - Sol avatar: A breathing, gradient orb avatar (40x40, radius 16, amber-coral radial gradient) with online status dot.
   - Title: `Sol` (bold 17, color `#3A3125`), subtitle: `Always here · Non-clinical companion`.
   - Action icon: Support icon (`health_and_safety_outlined`) to quickly access resources.

3. **Message Stream**:
   - Initial greeting from Sol:
     `"Hello. Take your time here. Whatever you're holding today, you don't have to carry it all by yourself. What feels present right now?"`
   - AI bubbles: Warm surface `#FFF8E8`, subtle amber border `0x24FFB534`, 22px radius (bottom-left 6px for speech tail), dark ink text `#46382A`.
   - User bubbles: Warm coral `#FFE2D4`, 22px radius (bottom-right 6px), dark coral-ink text `#46382A`.
   - Timestamps: subtle 11px font `#B7A98F`.

4. **Prompt Suggestion Chips**:
   - Horizontal chips above the input bar:
     - `"I'm feeling a bit restless"`
     - `"Help me unwind tonight"`
     - `"Just want to vent"`
     - `"Notice where I am"`
   - Tapping a chip inserts it or sends it directly.

5. **Safety Integration (CRITICAL)**:
   - When the user taps send or submits text:
     - Screen the text using `widget.safetyController.assessText(source: 'chat', text: text)`.
     - If assessment level != clear (e.g. `urgentSupport` or `supportSuggested`), IMMEDIATELY push `SupportResourcesPage(safetyController: widget.safetyController, assessment: assessment, ...)`.
     - NEVER bypass safety screener.

6. **Input Bar**:
   - Rounded pill container (radius 26, background `#FFFDF4`, border `0x42FFB534`, shadow).
   - Mic icon button for switching to voice.
   - Clean TextField (`Hint: Speak or type what's here…`).
   - Send button: Gradient amber-to-coral circle with white arrow.

7. **Route Hook**:
   - Support `?route=chat` in `lib/features/onboarding/onboarding_gate.dart` for direct routing and testing.
   - Verify `flutter test` compiles cleanly without breaking existing tests.
