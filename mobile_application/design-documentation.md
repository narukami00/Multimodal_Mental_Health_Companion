# Mental Health App — UI/UX Design Documentation
**Phase: Requirements & Design (Android prototype, MVP scope)**

---

## 1. Design Philosophy

The app is built around one governing principle: **limited choice, single focus per screen.**

Mental-health tracking apps typically default to utility-app patterns (dense dashboards, many tabs, feature-parity navigation). This app deliberately rejects that. A user opening the app may be mid-crisis, mid-slump, or simply tired — every additional decision on screen is friction, and in this context, friction has a cost beyond usability.

Core tenets:
- **One primary action per screen.** Secondary options exist but are visually subordinate, never competing.
- **Task-focused navigation, not feature-parity navigation.** The chatbot, capture modes, etc. are *actions* reached through a flow, not top-level destinations.
- **Non-punitive tone throughout.** Missed check-ins, incongruence flags, and gaps in history are treated as neutral information, never failure or alarm.
- **Human-readable output by default.** Transcript and words before numbers and confidence scores. Raw model output (confidence %, scores) is available but never front-facing by default.
- **Trust-first data handling.** Camera/mic are always optional and framed as equal choices, never gated or shamed defaults.

---

## 2. Visual Identity

| Role | Hex | Usage |
|---|---|---|
| Primary | `#FFB534` (warm amber/orange) | Primary CTAs, active states |
| Secondary | `#FF7F50` (coral) | Secondary actions, crisis-resource accent, alerts (used sparingly, never as "warning red") |
| Neutral | `#FEFCE8` (soft cream) | Backgrounds |

**Style notes:** soft rounded corners, generous whitespace, soft drop shadows only (no harsh contrast), friendly rounded sans-serif typography. Nothing clinical, sterile, or "productivity app" in tone. Chart/data visuals use warm gradient tones, never standard red/green data-viz conventions.

---

## 3. Information Architecture

### Bottom Navigation (4 tabs, fixed)
1. **Today** — home, single primary action
2. **Journal** — history/timeline of past sessions
3. **Insights** — trends and patterns
4. **You** — profile, settings, habit tracking, export, crisis resources

The chatbot and check-in capture are **not tabs** — they are flows launched from Today, keeping the nav bar stable and the decision surface small.

### Full Screen Inventory (MVP)
1. Onboarding (4 screens)
2. Today (home) — normal state
3. Today (home) — missed check-in / re-engagement state
4. Check-in mode selection (text / voice / video)
5. Chatbot conversation screen
6. Journal (history list)
7. Session detail view (tap into a single entry)
8. Insights
9. You / Profile
10. Crisis resources screen *(destination — next pass)*

---

## 4. Screen-by-Screen Specification

### 4.1 Onboarding (4 screens)
1. **Welcome** — app intro, one warm sentence, single CTA.
2. **How it works** — explains the three check-in modes (text/voice/video) and that sessions are understood through what's said, voice, and face — whichever the user shares.
3. **Camera & mic permission (trust-first)** — contextualizes the OS permission request *before* it appears. States plainly that camera/mic are always optional. "Allow access" and "Not now, I'll use text" are presented as **equal-weight choices** — no dark pattern, no greyed-out skip.
4. **Crisis resources awareness** — one-time notice that support resources are always reachable from the You tab, so it's never a surprise later.

### 4.2 Today (home) — normal state
- Soft greeting + date, no clutter.
- **Primary CTA:** quick check-in (mood + optional short text/voice) — visually dominant.
- **Secondary, quieter:** "Talk it through" → opens chatbot session.
- Passive glance state: streak / last check-in, shown gently.
- Persistent, small, unobtrusive crisis-resource affordance (same location always).

### 4.3 Today (home) — missed check-in state
- Near-identical to normal state, warmer in tone only.
- Microcopy acknowledges the gap without guilt (e.g. "no pressure, whenever you're ready").
- Streak/history shown as neutral faded gap, not a "broken streak" or red warning visual.
- No modals, no interruptions.

### 4.4 Check-in mode selection
- Exactly 3 equal-weight choices: Text / Voice / Video, each with a one-line description.
- No mode defaulted or emphasized over another.
- Low-pressure framing ("You can switch anytime").

### 4.5 Chatbot conversation screen
- Call-style interface, not chat bubbles — no text input box.
- Central abstract soft shape (avatar) representing the AI listening/speaking — deliberately non-literal (not a robot/human face).
  - *Design opportunity flagged for next pass:* tie the shape's motion to detected user emotion in real time, rather than a generic idle animation — this is the most-seen screen in the app and worth a differentiated treatment.
- Subtle live captions beneath the avatar, low visual weight.
- Minimal call controls: mic mute, camera toggle, end session (coral accent, clear but not aggressive).

### 4.6 Journal (history list)
- Entries grouped by date, soft rounded cards.
- Each card: time, soft color-coded dot for detected state (warm palette variants, never harsh red/green), one-line snippet or mode label.
- No numeric scores visible in list view.

### 4.7 Session detail view
- Top summary card: overall session state in words (e.g. "Mostly calm, some tension"), soft color band — not numbers.
- Expandable timeline of utterances/moments, each with transcript snippet + soft state tag.
- Incongruence markers on specific rows: calm dual-tone dot (not a warning icon), tap for one-line plain-language explanation.
- If video was used: optional toggle for resting-face vs in-speech comparison, shown as a simple soft visual, not a chart.
- Option to add a note/tag for what event the session was about.
- **Design principle:** transcript-first, data second. Confidence scores and raw numbers are not shown by default — this is the human-readable layer.

### 4.8 Insights
- Segmented control: Week / Month.
- One soft gradient trend chart — never more than one chart visible at once.
- 2–3 sentence-based insight cards (e.g. "You tend to feel calmer after mornings you check in early") rather than stats/tables.
- Incongruence flags shown gently, informational tone, not warning-styled.
- *Noted gap for next pass:* an opt-in "more detail" view (likely nested in session detail rather than the tab itself) for users who want to see the underlying data the pipeline actually produces — the current default is intentionally soft, but shouldn't be the *only* option, given the precision the pipeline is built for.

### 4.9 You / Profile
- Profile area with streak shown gently (not gamified).
- Menu rows: Habit & medication tracking, Export my data, Therapist view, Privacy & data settings, Crisis resources & support (visually distinct but calm — findable, not alarming), App settings.

### 4.10 Crisis resources screen
- **Not yet designed — flagged as next-pass item.** Entry points exist (Today, You tab) but the destination screen itself needs its own design pass.

---

## 5. Explicitly Deferred (noted, not designed this round)

- Crisis resources destination screen (content, resource selection, layout)
- Empty states (first-use Today, empty Journal, Insights with insufficient data)
- Incongruence flag micro-interaction *in the moment* (currently only designed retrospectively, in session detail/Insights)
- Dark mode / accessibility pass
- Web dashboard (Android-first for MVP; web deferred entirely)

---

## 6. Explicitly Parked (from requirements phase, not design)

- Digital footprint / social activity tracking — pending supervisor input
- Sleep / wearable correlation
- Standalone coping-tool library (breathing/grounding exercises)

---

## 7. Feature-to-Screen Mapping (for traceability)

| Feature (from requirements doc) | Primary screen(s) |
|---|---|
| Daily check-in prompt | Today, Check-in mode selection |
| Chatbot conversation | Chatbot screen |
| Free-form journaling | Check-in flow (text/voice), Journal |
| Emotion pipeline output | Session detail, Journal, Insights |
| Incongruence flagging | Session detail, Insights |
| Missed check-in signal | Today (missed state), You (streak context) |
| Event–emotion linking | Session detail (tagging) |
| Resting-face vs in-speech comparison | Session detail |
| Long-term emotional memory | Chatbot (referenced in conversation), Insights (pattern cards) |
| Analytics/trends | Insights |
| Suggestions/next steps | Insights, possibly Today (contextual) |
| Exportable reports | You tab |
| Therapist-facing view | You tab |
| Crisis/safety layer | Persistent affordance (Today, chatbot, You) + dedicated screen (deferred) |
| Streaks/consistency | Today, You |
| Habit/medication tracking | You tab |
| User emotional profile (structural) | Underlies Insights, Chatbot memory, Session detail — not a user-facing screen |

---

*This document reflects the state of design decisions as of the requirements/design phase. Items in Sections 5 and 6 are acknowledged gaps or explicit scope cuts, not oversights, and should be revisited before implementation sign-off.*
