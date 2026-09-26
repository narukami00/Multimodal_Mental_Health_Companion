# Design Critique & Redesign Spec — Today Page Companion Widgets

**Target:** `lib/features/app_shell/today_page.dart`
- "Talk it through" card → actual method is `_buildSecondaryCard()` (spec refers to it as `_buildSolChatPrompt`)
- "CONVERSATION WITH SOL" card → `_buildRecentConversationCard(BuildContext)`

**Status:** critique + blueprint only. `today_page.dart` is NOT to be modified until this spec is approved.

**Font:** the app theme uses `Nunito` (`lib/core/theme/app_theme.dart:30`) — all type specs below assume Nunito.

---

## 1. Current UI Flaws

### 1.1 The "Talk it through" card (`_buildSecondaryCard`, lines 254–429)

| Flaw | Where | Why it hurts |
|---|---|---|
| Chunky boxed icon | lines 303–331: 48×48 terracotta gradient square (radius 18) with a white `Icons.forum_rounded` inside, plus its own drop shadow | A rounded-square badge with a speech-bubble glyph is the visual language of 2018 dashboard apps, not a calm mental-health surface. It competes with the headline for attention and adds a third saturated color block to a card that already has a gradient pill. |
| Redundant "chip" decorations | lines 339–345: a 6px terracotta dot before the eyebrow | The eyebrow is already uppercase, letter-spaced and colored. The dot adds nothing but noise — decorative punctuation for its own sake. |
| Three competing CTAs in one row | icon box (left) + gradient "Open chat" pill with `arrow_forward_rounded` (right) + gradient border around the card itself | The eye doesn't know where to land. Icon → title → pill → arrow = four focal points where there should be one. |
| Hard gradient pill button | lines 372–410: `#FF9E7A → #FF6F43` fill, white text, shadow, inline arrow icon | Highest-contrast element on the card sits on top of a low-contrast, warm, quiet card. It shouts. The arrow icon inside is pure ornament — the pill's text already says "Open chat". |
| Amber hairline border | line 266–269: `Border.all(#52FFB534, 1.2)` | A visible rim boxes the content in. The spec asks for no heavy high-contrast borders; this is the most visible line on the whole page below the fold. |
| Stacked micro-row | eyebrow (10px, w800) 3px above title (18px, w800) directly beside a 48px icon — three vertical alignment zones at once | The alignment between icon top, eyebrow baseline and pill center is approximate, never quite right, which reads as sloppy rather than confident. |

**Net effect:** the card reads as a "component" (icon + label + button) rather than an invitation. Nothing about it feels alive; everything about it feels assembled from parts.

### 1.2 The "CONVERSATION WITH SOL" card (`_buildRecentConversationCard`, lines 450–673)

| Flaw | Where | Why it hurts |
|---|---|---|
| Tiny avatar icon | lines 502–518: 26px amber-gradient circle containing a 14px `Icons.forum_outlined` glyph | At 14px, `forum_outlined` collapses into an unreadable blob. A gradient circle holding a dark glyph reads as a broken/unloaded image. Worst of both worlds: it's a container *and* an icon. |
| Pill-in-a-box "History" button | lines 534–567: bordered chip (`#40FFB534` border, `#18FFB534` fill) with `history_rounded` icon + "History (3)" | A second bordered chip on the same row as an uppercase tracked label. Small borders inside small borders — this is the definition of clunky. |
| Excerpt boxed again | lines 572–595: the quote sits in its own `#FFF7E6` container with its own `#26FFB534` border and 14px radius | The card already has a border; now the text inside has a border too. Nesting framed boxes is what makes the UI feel like a form, not a journal. The italic quote deserves air, not a cage. |
| Border on the card itself | lines 474–477: `Border.all(#387A5D3A, 1.0)` | Another visible rim. Together with the amber rim above, the page becomes a stack of outlined boxes. |
| Green status dot | lines 600–607: `#48BB78` dot + "Recent" text | The only cool/green color in an otherwise warm palette, and it sits next to a red-orange gradient pill — a traffic-light pairing. |
| Gradient "Resume" pill + arrow icon | lines 622–661 | Same problem as "Open chat": loud fill, white text, ornamental arrow. Two near-identical gradient pills in one screenful of cards makes the whole home screen feel templated. |
| Three rows, six containers | header row / excerpt box / footer row — the card has ~200px of height carrying ~4 lines of content | Density without hierarchy: the eye must hop across three separately-framed zones to read one short excerpt. |

**Net effect:** the recent-conversation card looks like an inbox item in a to-do app. It should look like a page torn from a journal that Sol is holding open for you.

### 1.3 Cross-cutting problems

1. **Icons are doing the work typography should do.** `forum_rounded`, `forum_outlined`, `history_rounded`, `arrow_forward_rounded` ×2 — five glyph instances across two cards, four of them decorative.
2. **Every element is framed.** Card border + icon box + chip border + excerpt box + pill button. Five rectangles of hierarchy where whitespace alone would carry it.
3. **Gradients used as emphasis instead of atmosphere.** Warm gradients should breathe in the *background*; here they're applied to small foreground objects (pills, icon squares), which is what makes them look cheap.
4. **No motion, no life.** Both cards are frozen. A mental-health surface should feel like it's calmly breathing, not rendering a static form.
5. **Inconsistent eyebrow system.** Primary card uses `dot + 11px/1.8 tracking` (lines 137–155), this card uses `dot + 10px/1.2`, the conversation card uses `10px/0.8` with no dot. Three variants of the same idea.

---

## 2. Aesthetic Direction

**One-line brief:** *editorial calm — a warm cream page where typography is the only ornament, and a single soft glow breathes behind the words.*

### 2.1 Layout

```
┌─────────────────────────────────────────────┐
│  SOL · AI COMPANION                14:32    │   eyebrow row, no boxes
│                                             │
│  Talk it through                            │   24px w800 headline
│                                             │
│  A quiet, private space to speak or write   │   15px body, 1.5 lh
│  whatever is on your mind right now.        │
│                                             │
│  Open chat →                                │   text-only CTA, amber
└─────────────────────────────────────────────┘
   ↳ soft radial amber glow, blurred, behind headline, breathing (3.2s)

┌─────────────────────────────────────────────┐
│  CONVERSATION WITH SOL           History ·3 │   text chips, no icons
│                                             │
│   “I keep replaying what she said at lunch…”│   16px italic, terracotta
│    _ _ _                                   │   hairline rule, not a box
│                                             │
│  Tuesday · Recent          Resume →         │
└─────────────────────────────────────────────┘
```

### 2.2 Typography scale (both cards)

| Element | Size / Weight | Tracking | Line-height | Color |
|---|---|---|---|---|
| Eyebrow | 11 / w800 uppercase | +1.6 | — | `#C2622F` (terracotta 70%) |
| Headline ("Talk it through") | 24 / w800 | −0.4 | 1.15 | `#3E2818` |
| Body / description | 15 / w500 | 0 | 1.5 | `#7B6A55` |
| Quote excerpt | 16 / w600 *italic* | 0 | 1.55 | `#4A3728` |
| CTA label | 15 / w800 | +0.2 | — | `#E86034` |
| Meta (date · Recent) | 12.5 / w600 | +0.2 | — | `#A5937C` |
| History link | 12.5 / w700 | +0.4 | — | `#B08A5E` |

Everything else is Nunito's own defaults. No icon glyphs anywhere in these two cards.

### 2.3 Color & surface

- **Card fill:** `#FFFDF8` at 88% opacity over the page gradient (`backdrop: BlurRadius 0` not needed — a 6% warm wash is enough).
- **Borders:** none. Zero `Border.all` on either card. Depth comes from shadow only:
  - `BoxShadow(color: 0x0F784614, blurRadius: 24, offset: (0, 8))` — a whisper of warmth beneath.
- **Radius:** 28 (Talk card), 24 (Conversation card) — slightly rounder than now, to soften the silhouettes now that rims are gone.
- **Accent:** a single terracotta-to-amber **text gradient** is *not* used; CTA is flat `#E86034` text. Gradients live only in the background glow.
- **Remove:** green status dot (replace with the meta text alone), all chip fills/borders, all white-on-gradient pills, both arrow icons, both forum icons, history icon.

### 2.4 Organic touches / motion

1. **Breathing ambient glow** (Talk card): a `RadialGradient` (`#FFB534` at 34% → transparent), blurred, anchored behind the headline, opacity oscillating `0.55 → 0.95 → 0.55` over **3.2 s**, `easeInOutSine`, infinite. Scaled `0.96 → 1.06`. This replaces the icon box as the card's "aliveness".
2. **Quote emphasis** (Conversation card): a 2px vertical hairline in `#E86034` at 45% opacity to the left of the excerpt, with a soft top-to-bottom fade (gradient brush) — an editorial pull-quote marker instead of a box.
3. **Eyebrow dot:** keep a *single* 4px dot in `#E86034` at 60% before each eyebrow — but no circle container, no border, just the glyph-sized dot. This becomes the one consistent eyebrow signature across all cards.
4. **CTA affordance:** "Open chat →" / "Resume →" are plain text with a typographic `→` (U+2192), not `Icon`. On tap the arrow nudges 4px right over 180 ms (`Curves.easeOutCubic`) and returns — a "breath in, lean forward" micro-interaction.
5. **History link:** text-only with a count superscript style: `History · 3`. No chip, no fill. Underline fades in on press.
6. **Respect reduced motion:** gate the breathing glow with `MediaQuery.disableAnimationsOf(context)` — if animations are disabled, render glow at a fixed 0.75 opacity.

### 2.5 Spacing

| Gap | Value |
|---|---|
| Card internal padding | `EdgeInsets.fromLTRB(24, 22, 24, 22)` |
| Eyebrow → headline | 14 |
| Headline → body | 12 |
| Body → CTA | 22 |
| Excerpt block vertical margin | 14 |
| Footer row top spacing | 16 |
| Between the two cards | 16 (single `SizedBox` — currently 14 + Padding(14) = inconsistent) |

---

## 3. Code Blueprint

Ready-to-paste structure for the designer implementer. Names/colors match §2. All `_buildSecondaryCard` / `_buildRecentConversationCard` bodies get replaced wholesale; call sites (lines 93–94) stay unchanged.

### 3.1 Shared helpers (add as private widgets at file bottom)

```dart
class _BreathingGlow extends StatefulWidget {
  const _BreathingGlow({this.color = const Color(0x57FFB534)});
  final Color color;

  @override
  State<_BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<_BreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (!_isTestEnvironment && !MediaQuery.disableAnimationsOf(context)) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.isAnimating) {
      return _glow(0.75, 1.0); // reduced-motion / test fallback
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _glow(
        0.55 + 0.40 * Curves.easeInOutSine.transform(_c.value),
        0.96 + 0.10 * _c.value,
      ),
    );
  }

  Widget _glow(double opacity, double scale) => Transform.scale(
        scale: scale,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [widget.color, widget.color.withValues(alpha: 0)],
            ),
          ),
          alignment: const Alignment(-0.6, -0.4),
        ),
      );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label, {this.color = const Color(0xFFC2622F)});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _TextCta extends StatelessWidget {
  const _TextCta(this.label, {required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: 0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Transform.translate(
            offset: Offset(v, 0),
            child: child,
          ),
          child: Text(
            '$label  →', // typographic arrow, NOT Icon
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Color(0xFFE86034),
            ),
          ),
        ),
      ),
    );
  }
}
```

> Implementation note for `_TextCta`: use a `GestureDetector.onTapDown/onTapUp` (or `StatefulWidget`) to drive the tween `0 → 4 → 0`; the sketch above shows the structure — the implementer may simplify to a plain `Text` if the nudge is dropped.

### 3.2 `_buildSecondaryCard` — "Talk it through"

```dart
Widget _buildSecondaryCard() {
  return Material(
    color: const Color(0xE6FFFDF8), // #FFFDF8 @ 90%
    borderRadius: BorderRadius.circular(28),
    shadowColor: const Color(0x0F784614),
    elevation: 0,
    child: InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () {
        final active = chatController?.activeConversation;
        if (active != null && active.messages.any((m) => m.isUser)) {
          onStartNewChat?.call();
        } else {
          onOpenChat?.call();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // organic breathing glow — replaces the 48px icon box
            const Positioned(
              left: -60, top: -70, width: 240, height: 240,
              child: _BreathingGlow(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _Eyebrow('SOL · AI COMPANION'),
                      const Spacer(),
                      Text(
                        timeStr, // e.g. DateFormat('HH:mm').format(now)
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA5937C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Talk it through',
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: Color(0xFF3E2818),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A quiet, private space to speak or write whatever '
                    'is on your mind right now.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF7B6A55),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _TextCta('Open chat', onTap: () { /* same logic as InkWell */ }),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

**Deleted from current version:** `Icons.forum_rounded` box (303–331), dot+label duplication (339–355), gradient "Open chat" pill + arrow icon (372–410), amber `Border.all` (266–269).

### 3.3 `_buildRecentConversationCard`

```dart
Widget _buildRecentConversationCard(BuildContext context) {
  if (chatController == null) return const SizedBox.shrink();
  return AnimatedBuilder(
    animation: chatController!,
    builder: (context, _) {
      final convs = chatController!.conversations;
      if (convs.isEmpty) return const SizedBox.shrink();

      final activeConv = chatController!.activeConversation != null &&
              chatController!.activeConversation!.hasUserMessage
          ? chatController!.activeConversation!
          : convs.first;
      final excerpt = activeConv.preview;
      final meta = '${activeConv.dateStr} · Recent';
      final count = convs.length;

      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Material(
          color: const Color(0xE6FFFDF8),
          borderRadius: BorderRadius.circular(24),
          shadowColor: const Color(0x0F784614),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              chatController?.switchConversation(activeConv.id);
              onOpenChat?.call();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── eyebrow row: NO avatar icon, NO history chip ──
                  Row(
                    children: [
                      const Expanded(
                        child: _Eyebrow('CONVERSATION WITH SOL'),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _openHistorySheet(context),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 2,
                          ),
                          child: Text(
                            count > 0 ? 'History · $count' : 'History',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: Color(0xFFB08A5E),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── editorial pull-quote: hairline instead of a box ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 2,
                        height: 46, // or double.infinity with IntrinsicHeight
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x73E86034),
                                Color(0x1AE86034),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '“$excerpt”',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF4A3728),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── footer: text only, no dot, no gradient pill ──
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: Color(0xFFA5937C),
                          ),
                        ),
                      ),
                      _TextCta('Resume', onTap: () {
                        chatController?.switchConversation(activeConv.id);
                        onOpenChat?.call();
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
```

**Deleted from current version:** 26px `forum_outlined` avatar circle (502–518), bordered History chip + icon (534–567), amber-bordered excerpt container (572–595), green status dot (600–607), gradient Resume pill + arrow (622–661), card `Border.all` (474–477).

### 3.4 Acceptance checklist for the implementer

- [ ] `grep -n "Icons\." lib/features/app_shell/today_page.dart` shows **no** `forum_rounded`, `forum_outlined`, `history_rounded`, or arrow icons inside these two cards (footer/primary-card icons are out of scope for this pass).
- [ ] Neither card contains `Border.all`.
- [ ] No `BoxDecoration` has both `gradient` and a size under 64px (i.e. no gradient pills/chips) inside these two cards.
- [ ] Breathing glow renders at fixed 0.75 opacity when `MediaQuery.disableAnimationsOf` is true, and in `flutter test`.
- [ ] Excerpt still clamps to 2 lines with ellipsis; `History · N` still opens the history sheet; card taps preserve current `onOpenChat` / `onStartNewChat` branching logic (line 287–292).

---

## 4. Skipped (deliberately)

- No new fonts, no new packages — Nunito + `→` character only.
- No shared `AppCard` abstraction; two local edits. Add one only if a third card adopts this language.
- Primary check-in card's icon CTA and the footer's icons are out of scope here — flag for a follow-up pass if the same critique applies.
