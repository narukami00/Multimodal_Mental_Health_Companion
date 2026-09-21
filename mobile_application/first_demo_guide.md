I'll give you a short stack recommendation first, then the consolidated spec, then the demo roadmap. I ran no new research this turn. Platform-specific claims (Android permissions, Flutter and React Native capabilities, Firebase behavior) come from what I know, and each should be verified at build time. I mark those as "verify" items in the spec.

# Stack recommendation: Flutter, with one caveat

**Go with Flutter.** Your reasons hold up, and a few more apply to this app:

- **Android-first with a custom UI.** Your designs (call screen, analytics, one-primary-card home) are bespoke, and Flutter renders its own pixels, so custom charts, animated progress bars, and call-style screens don't fight platform widgets.
- **Firebase support is first-class** (FlutterFire covers Auth, Firestore, Cloud Messaging).
- **Camera, microphone, and audio plugins are mature**, which matters for your capture layer.
- **A single codebase** covers a later iOS build if you want one.

React Native's real advantages are a larger JavaScript talent pool and easier web code sharing. Neither matters for a solo Android-first build with a marketing site, and you're already leaning toward a separate landing page.

**The caveat: native Android code will be needed anyway.** Usage-access (screen-time) collection and background location have no good cross-platform plugin story, so the footprint module will need Kotlin platform channels. Both frameworks have this limitation. It's the reason footprint sits late in the roadmap. Budget for it as a small native-code task, not a plugin install. (Verify: check current Flutter plugins for usage stats before writing native code. One may exist by now, but I can't confirm it.)

**Web:** a static marketing site with a download link, as you suggested. Don't port the app to Flutter web. Camera, background tasks, and privacy-sensitive features work far better native.

**Suggested architecture pattern:** feature-first folders, a state-management library you're comfortable with (Riverpod is a common Flutter choice), and repository interfaces in front of every external dependency. That last point is the backbone of your mock-first strategy, so it gets its own section below.

---

# Part 1: Product specification (consolidated)

## 1.1 Product definition

A wellness companion that captures daily emotional data (text, voice, video), turns it into reflection, pattern insight, and gentle recommendations, and can optionally share a curated view with a clinician. It is a wellness tool with clinical-adjacent features, not a diagnostic instrument, and copy must reflect that everywhere.

## 1.2 Design principles (decided)

1. **One primary action at a time.** The home screen shows one card chosen by state. Everything else is behind small menu buttons.
2. **Never overwhelm.** Limited choices, progressive disclosure, no full-app tour.
3. **Gentle, not mandatory.** Suggestions are nudges, confidence-gated, and appear only sometimes.
4. **Deterministic first.** Rules and user feedback (thumbs, ratings, completion, comments) are the primary signals. Learned components come later and must be explainable.
5. **Every model output is optional and nullable.** The app must work with no emotion model, with a low-confidence model, and in text-only mode.
6. **Declined decisions are completed decisions.** Users can revisit any choice from settings.
7. **Missing data is not failure.** A missed day is signal, not shame. Absence is compared to the user's own baseline.
8. **Weak signals never act alone on sensitive matters.** Footprint data, missed check-ins, and emotion inferences can inform, never trigger crisis handling by themselves.
9. **Honest about uncertainty.** A four-phase confidence ladder governs every insight.
10. **Consent is granular, revocable, and versioned.**

## 1.3 Feature list (final)

### Capture
1. Daily check-in (widget/notification; text, voice, or video, chosen per session)
2. Text chat with a call button that opens the live call interface (camera + voice, TTS responses)
3. Free-form journaling (text or voice)

### Signal and intelligence
4. Emotion output per session and as trends (from the emotion model; nullable, per-modality, with confidence)
5. Incongruence flagging (words vs. face/voice)
6. Missed check-in tracking as a baseline-relative engagement signal (three-tier response, see 1.6)
7. Event-emotion linking (user tags, free text, LLM extraction, canonical normalization)
8. Resting-face vs. in-speech affect comparison
9. Long-term emotional memory (triggers to states, referenced across sessions including by the chatbot)

### Reflection and output
10. Analytics dashboard and trend charts
11. Pattern and correlation insights (three-stage method, see 1.7)
12. Suggestions umbrella: reflective prompts, activity recommendations, feedback loop
13. Personal exportable reports
14. Clinician-facing view (curated, per-category grants, footprint section default-off)

### Safety
15. Crisis/safety layer (independent module, watches all user text, receives PHQ-9 item 9 live, owns the boundary with the recommender)

### Engagement
16. Streaks and consistency (missed day reads as signal)
17. Optional habit and medication tracking

### Foundation
18. User emotional profile and history model (the persistent per-user structure)

### Recommendation system
- **A.** Curated activity library (LLM-generated, human-reviewed; therapeutic entries need clinician sign-off)
- **B.** Onboarding baseline quiz (preferences, ERQ-S, GAD-7, PHQ-9; the last two are atomic blocks)
- **C.** Rule-based recommendation engine v1
- **D.** Suggestion feedback capture (thumbs, 1 to 5 stars, completion, skip with reason, free-form comment)
- **E.** "Help me know you better" fallback (merged with the onboarding progress bar)
- **F.** Safety boundary and hard-coded blocklist
- **G.** "Why this?" one-line explanation on tap

### Infrastructure and supporting features
- **H.** Swappable interfaces: `EmotionAnalyzer`, `LLMProvider`, `STTProvider`, `TTSProvider`, `FootprintProvider`, each with a mock implementation
- **I.** Event tagging system
- **J.** Insight confidence ladder (four phases)
- **K.** Insight feedback (rate and dismiss on every insight)
- **L.** Consent and data-locality controls (per-modality, per-category, per-purpose, versioned; "currently shared with" panel)
- **M.** Notification budget system with a distinct check-in channel
- **N.** Text chat mode (see feature 2)
- **O.** Independent crisis-screening module
- **P.** Library review script (automated checks plus two-tier approval)
- **Q.** Welcome-back flow for lapsed users
- **R.** Digital footprint module (screen time, time-of-day usage, app-category usage, narrow own-app notification latency; location later)
- **S.** "My footprint" view (see and delete your own recorded data)
- **T.** Footprint-aware recommender inputs (relative-to-baseline, optional context only)

### Explicitly out of scope (for now)
- Media and content recommendation (playlists, videos)
- Learned recommendation policy (Thompson Sampling): v2, but v1 must log context, action, and outcome
- Passive location (Phase 2 after the demo)
- Adaptive check-in timing from screen-time data (start with time-of-completion learning instead)
- Typing cadence, general notification latency, app-switching frequency
- Social media metadata and content access, communication metadata (excluded permanently)
- Big Five personality module
- Third-party integrations (calendar, wearables)
- Web app (marketing site only)

## 1.4 Onboarding specification

Onboarding is a **resumable checklist** with a progress bar, not a linear wizard.

**Step states:** `not_started`, `completed`, `declined`. Declined counts toward the bar.
**Weighting:** by effort, with each quiz question counted individually and lightweight decisions counted as one unit each.

**Tier 1: Gate (mandatory, about 1 minute, not on the bar)**
- Account creation (Firebase Auth)
- Wellness/medical disclaimer acknowledgment
- Basic data consent

**Tier 2: Core decisions (one at a time, each skippable, on the bar)**
1. Do you want daily check-ins? If yes, preferred time.
2. Preferred input: text, voice, or video (permission requested in context, at the moment of choice)
3. First check-in (offered, not forced; skipped if check-ins were declined)
4. "Do you work with a therapist or doctor?" If yes, the per-category sharing walkthrough; if no, marked declined, surfaced later in settings
5. Digital footprint group: one intro card, then one decision per signal, each with its own permission moment and an explicit "not now, ask me later"

**Tier 3: Baseline profile (resumable, on the bar)**
Order: activity preferences, constraints, interaction preferences, never-suggest list, then ERQ-S, then GAD-7, then PHQ-9.
- ERQ-S and preferences are resumable question by question.
- **GAD-7 and PHQ-9 are atomic blocks.** Partial answers are stored but not scored until the block is complete. **PHQ-9 item 9 is evaluated the instant it is answered**, routing to the safety layer.

**Home card priority (one card at a time):**

| Priority | Condition | Card |
|---|---|---|
| 1 | Safety flag active | Support resources |
| 2 | Check-in enabled and not done today | Today's check-in |
| 3 | Onboarding incomplete | Next onboarding step |
| 4 | Suggestion due (within the daily cap) | The suggestion |
| 5 | Default | Open journal or chat |

The onboarding bar stays visible at the top, always tappable, with a prompt cap (about one gentle reminder every few days), collapsing to a small dismissible chip after roughly two weeks of being ignored. At 100%, a brief congratulation, the bar disappears, and a one-time note explains what the baseline unlocked. Personalization visibly improves as sections fill, so the bar pays off at each stage. New questions added later simply create new incomplete steps.

## 1.5 Recommendation system details

**Inputs:** current state (emotion, nullable), event-emotion links (primary), preferences, per-activity outcome history, cooldown state, footprint deviations (optional).
**Output:** one suggestion at a time, confidence-gated.
**Confidence:** number of outcomes for an activity in a similar context multiplied by the consistency of those outcomes. High confidence surfaces proactively; low confidence goes to a low-pressure "try something new" slot or stays hidden.
**Daily cap:** 2 proactive suggestions per day (1 in the first two weeks), user maximum 3. User-initiated requests don't count.
**Skip reasons:** "not now" (no penalty), "not for me", "too hard".
**Cooldowns:** built in from day one, since repeated use decays effectiveness and inactivity restores it.
**Blocklist (hard-coded, learner-proof):** substances, self-harm-adjacent content, unsupervised extreme exertion, medical claims.
**Boundary with safety:** everyday incongruence gets a choice menu; acute-risk signals bypass the recommender entirely.
**Logging requirement:** every suggestion logs context, action, and outcome, so a bandit can replace the rules in v2 without a rebuild.

## 1.6 Missed check-in logic

- **Days 1 to 2 missed:** silent; log only.
- **Sustained drop against the user's own baseline** (for example, 3+ days when they normally check in daily): one no-guilt message and a one-tap low-effort option.
- **Sustained drop plus other signals** (declining trend, negative language, low ratings): raises the internal risk score; the safety layer decides. Missing alone never triggers it.
- **Never infer a cause.** Copy never explains why the user missed.
- **Clinician view:** shown as "engagement" against the user's own baseline, with a note that gaps have many causes.
- **Churn:** after a set cutoff (start with 14 days), nudging stops and a single sparse re-engagement message is used, followed by a welcome-back flow with no streak shaming.

## 1.7 Insight methodology

**Stage 1: descriptive from day one.** Comparison of means with the count shown, framed as observation.
**Stage 2: tentative patterns after a minimum sample** (start with about 10 occurrences of a tag plus a minimum number of comparison days). Use rank-based tests (Spearman, Mann-Whitney), correct for multiple comparisons, and use hedged language.
**Stage 3: lagged and personal-model analysis (v2).** Time-lagged analysis needs months of dense data.

**Confidence ladder:**

| Phase | Data state | What the user sees |
|---|---|---|
| 0 | No history | Onboarding-based defaults, framed as starting points |
| 1 | Sparse (under about 7 days) | Descriptive facts and a progress cue toward the first insight |
| 2 | Emerging | Tentative language, count shown, rate/dismiss control |
| 3 | Established | Confident language, still overridable |

Never fabricate a chart from too little data. Tag normalization into canonical categories is required, otherwise counts dilute and patterns never form. User feedback ("this doesn't feel right") is a first-class quality signal.

## 1.8 Safety architecture

- **Independent crisis-screening module**, separate from the chat LLM. Layer 1 is keyword and phrase rules as a floor; layer 2 is a classifier or a second LLM pass. It watches all user-generated text.
- **Interrupt capability:** it can take over a chat or call mid-conversation.
- **PHQ-9 item 9** is evaluated live.
- **Resource surfacing must be locale-aware.** Your users may be in Bangladesh or elsewhere, so a hard-coded US hotline is wrong. Build a region-based resource table from the start, and have someone verify the local entries. (This is a launch-blocker item, flagged in the roadmap.)
- **Non-punitive handling:** no lockouts, no accusatory language, and no automatic clinician notification without prior explicit consent.
- **Small local models are weak crisis detectors.** The chat model is not the safety net.

## 1.9 Data, storage, and privacy

- **Auth:** Firebase Auth. **Cloud data:** Firestore. **Local data:** on-device database for categories the user keeps local.
- **Per-category storage choice** (journals, audio, emotion history, profile, footprint), stored in the profile.
- **Video:** discarded after feature extraction; only derived outputs kept.
- **Audio:** opt-in, time-limited retention (for example N days, extendable); derived acoustic features may be kept.
- **Consent records:** separate from onboarding state, per modality and per purpose, timestamped, and carrying the version of the text shown.
- **Clinician access:** per-category grants, a visible "currently shared with" panel, and immediate revocation that stops future sharing.
- **Firestore security rules** get written early, including clinician-scoped rules.
- **Feature honesty:** the consent screen must say which features send data off-device (chat and extraction use a server-side or laptop LLM), because "fully local" mode can't offer them unless the LLM is also local.
- **Footprint:** derive on-device, upload daily summaries only, never raw traces; separate consent per signal and per purpose; clinician footprint sharing is a distinct default-off grant.

## 1.10 Clinician view (curated, drill-down)

Summary header (period, engagement pattern against the user's baseline, baseline scores with change over time); emotion trends with confidence and a clear self-reported vs. model-inferred label; incongruence and resting-vs-speaking flags with linked sessions; event-emotion patterns the user has not dismissed, with sample sizes; safety events and how they were handled; recommendation log; user-flagged items; notes or export; footprint section (default-off). Carries a plain statement that the data is self-tracked and model-inferred, not diagnostic.

## 1.11 Notifications

- One shared budget across types; check-in has priority.
- Check-in uses a distinct notification channel and visual weight, plus a home-screen widget.
- Quiet hours and per-type mute from day one.
- Reminder timing starts at the user's chosen time and shifts toward the time they actually complete check-ins.
- Missed check-in messaging follows section 1.6.

## 1.12 LLM roles

| Task | Model | Notes |
|---|---|---|
| Chat | Gemma (dev, via `LLMProvider`) | Persona plus injected memory |
| Event and tag extraction | Same LLM, structured JSON output | Normalize to canonical tags |
| Summarization | Same LLM | |
| Library generation (offline) | Any strong LLM | Human-reviewed |
| Crisis screening | Separate module | Not the chat model |

Pick the Gemma size to fit your laptop RAM. (Verify: Gemma 4 sizes and memory needs on the current docs, and how you plan to serve it, for example llama.cpp or an Ollama-style runner, since your app must reach it over a local network during development.)

---

# Part 2: Architecture for mock-first development

## 2.1 Interfaces (the backbone)

Every external dependency sits behind an interface with at least two implementations.

| Interface | Mock | Real (later) |
|---|---|---|
| `EmotionAnalyzer` | Seeded-random plus scripted scenarios ("incongruent day", "declining week", "flat baseline") | Teammate's server |
| `LLMProvider` | Canned or scripted replies | Gemma local, then server model |
| `STTProvider` / `TTSProvider` | Platform speech APIs or stubs | Server models |
| `FootprintProvider` | Generated daily summaries | Kotlin platform channel |
| `SafetyScreener` | Keyword rules (real, since it's deterministic) | Rules plus classifier |

**Emotion result contract (agree with your teammate now; this is the one point that can't drift):**
```
EmotionResult {
  sessionId, modality: text|voice|face,
  timestamp,
  valence: float?, arousal: float?,     // nullable
  labels: [{label, score}]?,            // nullable
  confidence: float?,                   // nullable
  modelVersion
}
```
Per-modality results are stored separately, never as a single fused score, because features 5 and 8 compare them.

## 2.2 Layering by emotion-dependence

| Layer | Depends on emotion model? |
|---|---|
| Auth, capture UI, journaling, text chat, quiz, library, feedback, notifications, tagging, streaks, export, settings, consent | No |
| Recommender v1, cooldowns, confidence gating, fallback state | Weakly (emotion is one nullable input) |
| Emotion trends, incongruence, resting-vs-speaking, emotion-based correlation | Yes (built against mock data) |

## 2.3 Data model sketch (feature 18)

```
users/{uid}
  profile: { prefs, constraints, neverSuggest[], storagePrefs }
  onboarding: { version, steps{ id: {state, answers, scored} }, weightDone, weightTotal }
  consents: [{ type, granted, at, textVersion }]
  quiz: { erqS, gad7, phq9 }  // scored only when the block is complete
  sessions/{id}: { type, modality, text?, audioRef?, at, emotionResults[], tags[] }
  events/{id}: { tag, canonicalTag, source: user|llm, sessionId, at }
  suggestions/{id}: { activityId, context, shownAt, outcome, rating, skipReason, comment }
  activityStats/{activityId}: { count, meanRating, lastShown, cooldownUntil, confidence }
  insights/{id}: { type, phase, text, evidenceCount, feedback }
  footprintDaily/{date}: { screenMinutes, hourlyBuckets, categoryMinutes }
  safety/{id}: { source, level, handledBy, at }
  shares/{clinicianId}: { categories[], grantedAt, revokedAt }
```
Log every suggestion as (context, action, outcome). Keep raw footprint and video off the server by design.

## 2.4 Suggested project structure (Flutter)

```
lib/
  core/        (theme, routing, result types, errors, config)
  data/        (repositories, local db, firestore, interface definitions)
  providers/   (mock and real implementations, swapped via config)
  features/
    onboarding/  quiz/  home/  checkin/  chat/  call/  journal/
    insights/  analytics/  suggestions/  library/
    safety/  footprint/  settings/  clinician/
  domain/      (rules engine, confidence ladder, baseline logic, stats)
```
Keep the rules engine and stats in `domain/` as pure Dart with no Flutter imports, so they're easy to unit test. This is where most of your deterministic value lives.

---

# Part 3: Demo roadmap

## What "demo" should mean

A working Android app where a person can go through onboarding, do check-ins and chats, receive suggestions that respond to their feedback, and see insights and analytics grow over time, all running on mock emotion data with a real Gemma-backed chat. The demo's job is to prove the **interaction design and the deterministic intelligence**, and to make your teammate's model a drop-in later.

**A key device for the demo: a "demo mode" that fast-forwards time.** A recommender and an insight ladder that need weeks of data are hard to show. Build a hidden dev panel that can seed N days of synthetic history (with scripted scenarios) and advance the app's clock. Without it you cannot demo phases 2 and 3 of the confidence ladder, or the recommender learning, in a single sitting. Treat this as a first-class deliverable, not a hack.

## Milestones

**M0: Foundations (about 1 week)**
- Flutter project, folder structure, theme from your designs, routing, state management, Firebase project
- Interface definitions and mock providers (H), including the emotion result contract
- Local database and repository layer
- Deliverable: app boots, navigates between empty screens, mocks are injectable

**M1: Identity, consent, onboarding shell (about 1 to 1.5 weeks)**
- Firebase Auth, disclaimer, basic consent, versioned consent store (L)
- Onboarding checklist engine with the progress bar and the three step states
- Tier 2 decisions (check-in choice, modality with in-context permissions, clinician question)
- Home screen with the one-primary-card priority logic
- Deliverable: a new user can sign up, decline or accept things, and see the right home card

**M2: Capture (about 2 weeks)**
- Daily check-in flow (text, voice, video capture UI; stub analysis)
- Journaling (text, voice)
- Text chat wired to Gemma through `LLMProvider`, with the call button opening the call screen (call screen uses mock TTS/STT at first)
- Session history and logging
- Deliverable: all three capture modes work end to end and save sessions

**M3: Safety skeleton (about 1 week, start early, finish before any external testing)**
- Independent `SafetyScreener` with the keyword floor, wired into chat, journal, and check-in text
- Interrupt behavior mid-chat, the resource screen, region-based resource table (structure now, verified content before launch)
- Deliverable: a test phrase in chat reliably triggers the support flow

**M4: Quiz and profile (about 1.5 weeks)**
- Preference questions, ERQ-S, GAD-7, PHQ-9 with atomic blocks and the live item-9 check
- Scoring, storage in the profile model (18)
- Resumable progress-bar behavior (merged with feature E's entry point)
- Deliverable: a user can complete or partially complete the baseline, and PHQ-9 item 9 triggers safety

**M5: Activity library and review script (about 1 week, can run parallel to M4)**
- Library schema, generation script (P), automated checks including the blocklist, review step
- Seed the app with an approved starter set (start with a small, well-reviewed set, for example 40 to 60 entries)
- Deliverable: reviewed library JSON loads into the app

**M6: Recommender v1 (about 2 weeks)**
- Rules engine in `domain/`: eligibility, cooldowns, confidence, daily cap, blocklist
- Suggestion card, "why this?", feedback capture (D), skip reasons
- Event tagging (I): user tags, free text, LLM extraction with structured output, canonical normalization
- Fallback state (E)
- Deliverable: suggestions appear, respond to feedback, and adapt over simulated days

**M7: Insights and analytics (about 2 weeks)**
- Analytics dashboard against mock emotion data
- Stage 1 and 2 correlation logic, the confidence ladder, insight feedback (K)
- Missed-check-in baseline logic and the three-tier response (6, Q)
- Streaks (16)
- Deliverable: dashboard and insights render at each ladder phase, and each state is reachable in demo mode

**M8: Notifications and engagement (about 1 week)**
- Notification budget (M), distinct check-in channel, widget
- Quiet hours, time-of-completion learning
- Deliverable: check-in reminders behave per spec

**M9: Reflection outputs (about 1.5 weeks)**
- Long-term memory injection into chat (9), kept subtle per your gentle-nudge rule
- Personal export (13)
- Clinician view (14) with per-category grants and the "currently shared with" panel
- Habit and medication tracker (17), the lowest-priority item here, cut first if time runs short
- Deliverable: a shareable clinician view generated from demo data

**M10: Demo mode and polish (about 1 week)**
- Synthetic-history seeder with scripted scenarios, time fast-forward
- Empty, low-data, and low-confidence states everywhere
- Performance, accessibility pass
- Deliverable: a scripted walkthrough that shows every major feature in about 15 minutes

**Total: roughly 15 to 17 weeks solo** by these estimates. I don't know your speed, availability, or how many parts an AI coding agent will handle, so treat these as ordering guidance, not commitments. If time is tight, the safe cuts are: habit tracker, clinician view drill-down, and call-screen polish.

**Phase 2 (after the demo):** the real emotion model integration, footprint module (Android Kotlin collectors, then the "my footprint" view and recommender inputs), passive location, real STT/TTS, learned policy, and adaptive timing experiments.

## Where the ML model plugs in
Integration is a config swap of `EmotionAnalyzer`, plus checks on the contract (nullability, per-modality outputs, latency). Because everything downstream already tolerates null and low confidence, nothing else should need rework. Ask your teammate early for **five to ten real sample outputs**, so your mock generator mirrors realistic distributions instead of uniform noise.

---

# Part 4: Items to research during development

Point your coding agent at these before implementing the relevant milestone. Each is a bounded question.

| Milestone | Research item |
|---|---|
| M0 | Riverpod (or your chosen state library) patterns for swappable providers; Firestore offline persistence behavior; Firestore security rule patterns for user-owned and clinician-scoped data |
| M1 | Firebase Auth options; consent-record schema and legal wording for your target region (get it reviewed) |
| M2 | Flutter camera and microphone plugin choices; audio recording formats and size; reaching a laptop-hosted Gemma from an Android device on a local network; streaming responses |
| M3 | Locale-appropriate crisis resources for your target countries (needs a human to verify); keyword lists in every language you support (Bangla, if applicable); how established chat apps handle mid-conversation interruption |
| M4 | **Licensing and permitted-use terms for ERQ-S, PHQ-9, and GAD-7 in a commercial app** (PHQ-9 and GAD-7 are widely available but check current terms); validated translations if you support another language |
| M5 | Review criteria for activity evidence tiers; contraindications per activity type |
| M6 | Tag normalization approach (embedding clustering vs. an LLM canonicalizer with a fixed vocabulary); structured-output reliability on small local models |
| M7 | Chart library choice for Flutter; exact test and multiple-comparison correction to use; minimum sample thresholds |
| M8 | Android notification channel behavior and battery-optimization interference with scheduled reminders (vendor-specific OEM restrictions are a known pain point); widget support in Flutter (usually needs a native plugin) |
| M9 | Clinician-side access model (does the clinician need an account or a link?); export format |
| Phase 2 | Current Android Usage Access flow and Play policy for usage and location permissions; battery cost of background location; whether Flutter plugins exist for usage stats |

## Launch-blockers (not demo-blockers)
Before anyone outside your team uses it: verified regional crisis resources, reviewed consent and privacy text, licensing confirmed for the questionnaires, a decision on clinical validation claims, and a legal check on health-data handling in your target market.

---

# Summary handoff block

If you need to pass this to another LLM, the essential points are:

- **What:** Android-first Flutter wellness app; emotion capture (text/voice/video); a teammate builds the emotion model separately, so all model outputs go through nullable, per-modality, mockable interfaces.
- **Core principles:** one primary action at a time; gentle confidence-gated suggestions; deterministic rules and user feedback first; weak signals never act alone on sensitive matters; declined decisions count as completed; consent granular and versioned.
- **Intelligence:** rule-based recommender with cooldowns, daily cap, blocklist, and full logging for a future bandit; a four-phase confidence ladder; three-stage correlation; baseline-relative missed-check-in logic.
- **Safety:** an independent crisis-screening module (not the chat model), PHQ-9 item 9 evaluated live, locale-aware resources.
- **Onboarding:** a resumable checklist with a progress bar; a short mandatory gate; PHQ-9 and GAD-7 as atomic blocks.
- **Footprint:** Android-first, passive, screen-time and app-category first, on-device summaries only, location later, social content and communication metadata excluded.
- **Roadmap:** M0 to M10 as above, with demo mode (synthetic history plus time fast-forward) as a first-class deliverable.

If you want to continue in a new chat, I'd suggest starting with either the **activity library schema and starter entries** (M5) or the **onboarding and quiz flow screen by screen**, since those are the two areas with the most unspecified design detail left.