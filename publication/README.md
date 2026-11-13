# Solace SoftwareX release plan

Prepared 2026-11-13 from the application checkout and the current demo engine in
the externally supplied dataset workspace. This is an implementation proposal,
not a statement that authentication, encryption or user correction already exist.

## Implementation checkpoint (2026-11-13)

- **Phase 1 (Reproducibility & optional Firebase authentication)**: Implemented and committed (`9279dbe`, `c02e363`, `d2e6ba6`, `00bb017`). `emotion_server` is extracted with hash verification (`7/7` service artifacts verified, `6/6` backbones/face present unverified). `companion_server` enforces Firebase ID token verification, owner-bound sessions, and WebSocket authorization headers. Flutter supports optional Firebase sign-in/sign-up, re-authentication, account deletion, and device-ownership isolation.
  - Remaining external step: `mobile_application/android/app/google-services.json` is not present in the repo and must be downloaded from the Firebase Console by the project owner before live Firebase Auth / Google Sign-In can run on a device.
- **Phase 2 (Journal mood confirmation & provenance)**: Implemented and committed (`992f62f`). Model abstention is preserved (no fallback to neutral), reading cards offer *Does this fit?* (*Yes* / *Not quite* / *Skip*) and *How did you feel then?*, user corrections take precedence over model estimates, reanalysis preserves user corrections, and exports/therapist summaries distinguish source provenance.
- **Phase 3 (Chat trajectory review & agreement statistics)**: Implemented and committed (`61d1352`). Conversation breakdowns record independent shift-fit and proposed-context agreement without mutating model scores, and display explicit counts/denominators without claiming clinical or classifier accuracy.
- **Phase 4 (Encryption, consent & data lifecycle)**: Implemented and committed (`3b4f7e5`). Added `AndroidKeystoreCipher` (`AES/GCM/NoPadding` over `MethodChannel`) + atomic `.tmp` write-readback-rename for sensitive repositories and pending recordings, Android Auto Backup / device-transfer exclusion, send-time emotion/face consent recheck + server-side `X-Solace-Consent-*` enforcement, orphan/retention cleanup, avatar cleanup, all-notification cancellation on erase, and explicit `local_only` TTS mode.
- **Verification observed**:
  - `dart scripts/verify_emotion_consent.dart`: PASS
  - `python -m unittest discover -s emotion_server -p test_cue.py`: PASS (20/20)
  - `python emotion_server/check_assets.py --verify-hashes --face`: PASS (`7` verified, `6` present_unverified)
  - `python -m unittest discover -s companion_server -p "test_auth_*.py"`: PASS (20/20)
  - `pytest` (`test_turn_detector.py`, `test_session_logic.py`, `test_conversation_memory.py`, `test_memory_prompt.py`, `test_tts_chunker.py`, `test_journal_api.py`): PASS (85/85)
  - `flutter analyze`: PASS (0 issues)
  - `flutter test`: 1604 passed, 2 skipped, 1 failed (`permissions_page_test.dart` due to updated privacy copy, then fixed and re-run: 9/9 passed).
  - `flutter build apk --debug`: PASS (`build/app/outputs/flutter-apk/app-debug.apk`), installed on USB device `R3CRC0LYLWP`.
  - Not executed / blocked: live Firebase Auth device sign-in (missing `google-services.json`), live end-to-end GPU model inference smoke test, and target-user clinical/usability study.

## Release scope

- Release the Flutter app, companion server and a versioned **reference demo
  emotion backend** together. Keep the emotion backend behind the existing API so
  the separately developed research pipeline can replace it.
- Describe emotion estimates as optional, uncertain inputs. Do not claim a
  novel or superior emotion classifier solely because the app is multimodal.
- The intended initial language is English. Evaluate the supported language;
  adding Bangla is not a prerequisite for this release.
- Keep manual self-care useful without an account, internet or inference server.
  Optional online inference can require an authenticated account.

## 1. Reproducible reference backend

The `emotion_server` directory packages runtime source separately from the
dataset preparation and training workspace. Follow its README for the exact
status of model assets, dependencies and verification. A source package alone
does not establish a fully reproduced inference deployment.

Release acceptance:

- A fresh setup can start the documented API with licensed, identifiable model
  artifacts and calibration statistics; no developer-specific absolute imports.
- Artifact origins, versions, hashes and redistribution/download conditions are
  documented. Restricted raw datasets and private recordings are not bundled.
- A model-free contract/demo path and failure cases can run without a GPU.
- A real-model smoke test and capture-to-result latency are recorded separately.
- Freeze the evaluated release. Report MELD production-reference normalization
  separately from exploratory own-domain-statistics results.

## 2. Optional account and authenticated inference

Recommended provider: Firebase Authentication, email/password and Google.
Firestore and automatic journal synchronization are not needed for identity.

User experience:

- Preserve local-first startup. Integrate an optional account choice with the
  final name/profile onboarding step; provide **Continue on this device**.
- Google can prefill available name/photo, with editable confirmation and
  fallbacks. Email sign-up collects a chosen name; photo remains optional.
- Require online sign-in when enabling hosted inference. Preserve journaling and
  queued recordings when offline or a token refresh fails.
- Support password reset, email verification where required, sign-out and account
  deletion/re-authentication. Never collect or store passwords in app preferences.
- Account identity and local self-care preferences remain separate. Explicitly
  associate existing local data with an account; isolate subsequent users. Never
  silently upload or reassign someone else's history after account switching.

Backend acceptance:

- Verify Firebase ID tokens on the companion server; derive identity from the
  verified UID. Reject missing/invalid/expired tokens and unauthorized sessions.
- Bind sessions, chat/video streams and journal requests to their owner. Enforce
  relevant consent at processing time, not only in the Flutter interface.
- Protect public transport with HTTPS/WSS; bound uploads, concurrency and rates.
  Protect credentials and avoid placing reusable tokens in URLs or logs.
- Keep the internal emotion API on loopback/private networking behind the
  companion. Firebase login does not itself protect this internal API.
- Reproduction can use a documented local authentication emulator/test fixture;
  production must not silently fall back to unauthenticated processing.

## 3. User report and model estimate

- Extend the existing `SessionRecord`/`EmotionResult` structure instead of
  replacing the seven-class model taxonomy with the five UI mood words.
- Keep original self-report, timestamped user correction and model result
  separate. Existing model version, confidence, origin and modality fields remain.
- On an entry's reading card, offer **Does this fit?** with **Yes**, **Not quite**
  and **Skip**. Correction asks **How I felt then**. Include **None fits**.
- Ask **How are you feeling now?** separately when useful for an immediate
  recommendation; an old journal describes an earlier time.
- Downstream policy: explicit user report/correction takes precedence. Allow
  eligible model fallback only without self-report and with relevant consent.
  Preserve unknown/abstention; missing inference must not become neutral mood.
- Reanalysis must preserve user corrections. Charts, PDF and research exports
  must distinguish the source rather than pool everything as self-report.
- Corrections improve the user's record immediately. Do not automatically
  retrain the model or send corrections to research. Research/training reuse needs
  separate consent, versioned datasets and held-out evaluation.
- Extend optional review to chat trajectory summaries: ask separately whether
  the emotional shift fits and whether the proposed context/reason fits. A
  model-proposed cause is a hypothesis, not a causal finding. Retain the exact
  estimate/summary version that was reviewed.
- Personal review statistics must show counts, denominators and unanswered
  readings. Report user-confirmed fit among reviewed estimates, not clinical or
  classifier accuracy. Keep mood-fit and proposed-reason agreement separate.

## 4. Privacy and data lifecycle

- Preserve intentional offline capture: temporarily retain a queued recording,
  process it when available/allowed, then remove the raw pending files.
- Encrypt sensitive repository content and pending audio/face features at rest
  using authenticated encryption and a platform-protected key. Plan migration,
  crash recovery and tamper handling before replacing stores.
- Recheck voice/text and face consent independently at every queued upload.
  Revoking face consent must prevent pending face measurements from being sent.
- Verify deletion and reconcile orphan files. Document retry timing, retention
  and user cancellation; foreground retries are not a guaranteed background job.
- Make backups intentionally portable and sensitive: device-only keys cannot
  decrypt a backup on a replacement phone. Design encrypted portable backups
  separately from normal device storage.
- Include avatars and temporary export files in file ownership/deletion rules;
  current preference-only backup does not carry avatar image bytes.
- Ordinary server inference decrypts input while processing. Encryption at rest
  and TLS protect stored data and network transit, not against the inference
  process itself. Do not label this end-to-end encrypted/server-blind inference.
- Offer an explicit local-only speech mode; no silent cloud TTS fallback in it.
  Distinguish server-side STT from optional cloud TTS in user-facing explanations.

## 5. Safety scope and evaluation

- Describe implemented behavior accurately: recognized crisis-related language
  opens support options and can select a fixed response. This is not emergency
  treatment or guaranteed crisis recognition.
- Test English paraphrases, indirect distress, negation, quotations, benign
  mentions and missed matches; keep support reachable without an AI prediction.
- Reuse the existing evaluation protocol, ablations and research export. Existing
  classifier benchmark outputs do not substitute for target-user app evaluation.
- Run engineering/reproducibility checks first; then an ethically approved
  usability study of the five core journeys. A longer study is needed for phone
  baselines and engagement claims. No clinical efficacy claim from usability alone.

## Order and completion evidence

1. Freeze reference backend/interface, model artifacts and release instructions.
2. Add optional account identity and enforce inference/session authorization.
3. Implement source-aware mood correction and protect the offline queue.
4. Complete encrypted local storage, deletion/revocation and transport checks.
5. Freeze a study build; execute engineering checks and target-user evaluation.
6. Write the software paper using the actual release and measured results.

References: [Firebase Flutter authentication](https://firebase.google.com/docs/auth/flutter/start),
[backend token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[Android Keystore](https://developer.android.com/privacy-and-security/keystore),
[SoftwareX reviewer form](https://legacyfileshare.elsevier.com/promis_misc/softwarex-reviewer-form.pdf).
