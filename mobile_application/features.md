Here is the finalized spec. I've set the daily cap myself (see #4 below), flagged two consequences of your calls that need handling, and kept your original numbering for the existing 18 features so nothing gets lost.

## Decisions I made on your behalf

**Daily suggestion cap: 2 proactive suggestions per day, 1 in the first two weeks.** The reasoning: habituation is real, low-mood users are the most easily overwhelmed, and one well-timed suggestion beats three ignored ones. User-initiated requests ("give me something to do") don't count toward the cap. Users can lower it in settings, but not raise it above 3. This is one config value, so it's cheap to change after you see real data.

**Two consequences of your calls to handle:**

1. **Full PHQ-9 + GAD-7 means item 9 must trigger the safety layer.** A nonzero response on PHQ-9 item 9 has to route into feature 15 immediately, with resource surfacing and non-punitive handling, and it can't just be stored as a score. Also decide whether the quiz is skippable. I recommend the screening section is skippable, but the safety path is always on for any response.
2. **LLM-generated library needs a review gate.** "LLM generated and reviewed" only holds if nothing reaches users unreviewed. I've made that a hard requirement (feature A below), with a clinician sign-off tier for anything tagged as therapeutic rather than lifestyle.

## Finalized feature list

**Capture** (unchanged)
1. Daily check-in prompt (widget/notification), text, voice, or video
2. Live chatbot conversation (camera + voice, call-like) with TTS responses
3. Free-form journaling (text or voice)

**Signal / Intelligence** (unchanged)
4. Emotion pipeline output, per-session and as trends
5. Incongruence flagging
6. Missed check-in tracking as its own signal
7. Event–emotion linking
8. Resting-face vs in-speech affect comparison
9. Long-term emotional memory

**Reflection / Output**
10. Analytics dashboard / trend charts
11. Pattern and correlation insights
12. **Suggestions and next steps (restructured).** Now the umbrella for three layers: reflective prompts at low severity, activity recommendations at moderate severity, and the feedback loop (D below), blended by context. Implemented by features A, C, D, E, and G.
13. Exportable reports for personal use
14. Clinician-facing view (**extended:** shows suggestions offered, completion, ratings, skip reasons, and the baseline scores)

**Safety**
15. Crisis/safety layer (**extended:** receives PHQ-9 item 9 responses; owns the boundary with recommendations, see F)

**Engagement**
16. Streaks and consistency mechanics
17. Optional habit/medication tracking

**Foundation**
18. User emotional profile / history model (**extended:** now also stores baseline quiz results, preferences, activity outcome history, cooldown state, per-activity confidence, and the never-suggest list)

**New: Recommendation system**

**A. Activity library (curated, internal).** LLM-generated, human-reviewed before release. Each entry is tagged with type (movement, social, creative, nature, mindfulness, learning, productivity), effort, duration, required context, target state, and an evidence tier. Entries tagged therapeutic (such as CBT-style exercises) need clinician sign-off; lifestyle entries need reviewer sign-off only. Nothing ships unreviewed.

**B. Onboarding baseline quiz.** Two parts, about 3 to 4 minutes total.
- Part A, who you are: ERQ-S (6 items), PHQ-9, GAD-7. Use validated wording verbatim and check the licensing terms for each instrument. The symptom screen is skippable; the safety routing is not.
- Part B, what you like: activity preference checklist, constraints (time, energy patterns, physical limits, living situation), interaction preferences (frequency, timing, tone, modality), and the explicit never-suggest list.
- A shorter re-quiz variant is reused by feature E.

**C. Recommendation engine v1 (rule-based, deterministic).**
- Inputs: current state, event-emotion links (your primary context signal), stated preferences, per-activity outcome history, and cooldown state.
- Output: one suggestion at a time, confidence-gated. High confidence surfaces proactively; low confidence goes only into a low-pressure "try something new?" slot or stays hidden.
- Confidence is defined as the number of past outcomes for an activity in a similar context multiplied by the consistency of those outcomes.
- Cooldowns are built in from day one, since repeated use decays effectiveness and inactivity restores it.
- When incongruence or ambiguity is present, offer a choice instead of deciding for the user.
- Daily cap as set above.

**D. Suggestion feedback capture.** All of these count as reward signals: thumbs, 1 to 5 stars, completion, skip, and free-form voice or text comment. Skip requires one tap for a reason: "not now," "not for me," or "too hard." "Not now" does not penalize the activity.

**E. "Help me know you better" state.** Triggered by repeated rejection. Step one offers the short re-quiz; if that is declined, the app drops to very low suggestion frequency with a passive, dismissible "help me know you better" entry point. Two guardrails: it never blocks core capture and reflection features, and the prolonged-decline pattern feeds feature 6 and is visible to feature 15 as a possible risk signal alongside other indicators.

**F. Safety boundary and blocklist.** A hard-coded set of rules the learner cannot override. It bars categories such as substance use, self-harm-adjacent content, and unsupervised extreme exertion. It also defines the split with feature 15: everyday incongruence gets a choice menu, acute-risk signals bypass the recommender entirely and go to the safety layer.

**G. Explainability on tap.** Suggestions stay gentle and unexplained by default, but a tap on "why this?" reveals a one-line reason drawn from the user's own history. This keeps the low-pressure feel of your #6 while preserving transparency.

## Explicitly deferred

- **Media and content recommendation** (playlists, videos): backlog. The rumination findings from earlier apply when you return to it: mood-matching is the wrong objective.
- **Learned policy (Thompson Sampling or similar):** v2, once you have a few weeks of feedback data. The v1 data model should log everything a bandit would need (context, action, outcome) so the upgrade is a swap, not a rebuild.
- **Big Five personality module:** dropped from the MVP baseline; emotion regulation style and preferences carry more weight for recommendations.

## Build-order dependency note

Feature 18 (profile model) and A (library) are prerequisites for everything else in the recommendation layer. B (quiz) feeds 18. C, D, and E can't be tested without A and B. F should be built alongside C, not after it. That gives you a natural sequence: **18 → A + B → F → C → D → E → G.**

## Digital footprint / digital phenotyping — candidate signals

**Device & usage-pattern level (lowest sensitivity, doesn't require reading content)**
- Overall screen time (daily total, trend over time)
- App-switching frequency / session count per day
- Time-of-day usage pattern (e.g., heavy use 2–4am as a possible sleep-disruption proxy)
- Typing speed / cadence changes over time (not content, just rhythm) 🚩 *(still a behavioral biometric — some users find this invasive even without content access)*

**App-category level**
- Which *categories* of apps are used and for how long (social, entertainment, productivity) without knowing what's posted/viewed inside them
- Notification response latency (how quickly/rarely notifications are opened) 🚩

**Social media — activity metadata (no content access)**
- Login/active frequency on a given platform (opted-in, per-platform)
- Posting frequency trend (more/fewer posts than their own baseline)
- Time-of-day posting pattern
- Sudden drop in activity (a well-documented signal — withdrawal is often more predictive than any single post) 🚩 *(requires platform API/OAuth access — most platforms don't expose this without it)*

**Social media — content-level access** 🚩🚩
- Sentiment/tone of posts (text analysis of what they actually post)
- Topic shifts in posting content
- Comment/interaction tone on others' posts
*(This tier is the one most likely to need serious supervisor + ethics/IRB-style discussion — it's the difference between "did they post less" and "reading what they said")*

**Communication metadata** 🚩🚩🚩
- Frequency of messages/calls (not content) — this is the one you explicitly ruled out, and worth staying firm on; even *frequency-only* tracking of private messages is one of the most legally and ethically loaded categories (wiretap-adjacent in some jurisdictions)

**Location/mobility** 🚩
- Time spent at home vs. away (isolation proxy) — "% time at home" is one of the most established markers in published depression/anxiety digital phenotyping research
- Movement radius/variability day-to-day

