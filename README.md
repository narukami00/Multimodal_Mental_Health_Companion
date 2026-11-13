# Solace: Local-First Reflective Journaling & Adaptive Self-Care Companion

Solace is a privacy-preserving, local-first mobile self-care application and optional authenticated AI companion architecture built with **Flutter (Android)** and **Python (FastAPI / WebSockets)**. It combines structured self-care journaling, behavioral pattern awareness, source-aware affective reflection, adaptive on-device personalization, and optional real-time voice/text dialogue with an AI companion ("Sol").

> **Research & Non-Clinical Scope**
> Solace is a reflective self-care research software platform. Emotion estimates are presented explicitly as uncertain, optional hypotheses (preserving model abstention) rather than clinical assessments. Crisis-phrase detection surfaces static support resources and never replaces emergency care or human clinical judgment. Standard HTTPS/WSS + AES-GCM local storage protect transit and device rest, while ordinary companion/emotion server inference processes requests in plaintext on the host running inference.

---

## Architecture Overview

Solace decouples local self-care from optional cloud identity and heavier GPU inference:

| Component | Path | Responsibility |
|---|---|---|
| **Mobile Client** | `mobile_application/` | Local-first Flutter Android app: check-ins & reflective journal, growing forest metaphor, keyword-searchable chat history, on-device Android Keystore encryption, source-aware mood confirmation/calibration, gentle periodic check-ins, and consent controls. |
| **Companion Gateway** | `companion_server/` | FastAPI + WebSocket server (`/v1/sessions`, `/ws/v1/session`, `/ws/v1/video`, `/v1/journal/*`): Firebase ID token verification (owner-bound ephemeral leases), Silero VAD + turn detection, Faster-Whisper STT, LLM response streaming with sanitized consented memory, local/cloud TTS (`local_only` toggle), and safety gating. |
| **Emotion Reference Engine** | `emotion_server/` | Extracted multimodal affect service (audio/text/face heads + hedged cue builder & manifest SHA-256 verification) kept strictly on loopback behind the authenticated companion gateway. |
| **Release & Verification** | `scripts/`, `publication/` | Model-free reproducible verification (`scripts/verify_release.py`, `scripts/verify_emotion_consent.dart`) and SoftwareX readiness & evaluation notes (`publication/README.md`). |

---

## Key Privacy, Provenance, and Personalization Guarantees

1. **Local-First & Optional Identity**
   - Manual journaling, mood tracking, coping activities, insights, and backup export/import work fully offline with no Firebase account or remote server.
   - Signing in with Firebase Auth (Email/Password or Google) unlocks companion/emotion inference and enforces **device-account ownership isolation** so local records never silently merge across accounts.
2. **Encrypted Storage & Fail-Closed Consent**
   - Sensitive repositories (journals, chats, moments, profile, therapist contact, consent ledger, safety events) and queued offline recordings (`.pcm.enc`, `.face.enc`) use `AES/GCM/NoPadding` keys in **Android Keystore** with atomic `.tmp` write-readback-rename persistence and Android Auto Backup / device-transfer exclusion.
   - Emotion (`v2.0`) and face (`v2.0`) scopes require explicit versioned agreement and are rechecked both client-side before queued upload and server-side via `X-Solace-Consent-*` headers.
3. **Human-in-the-Loop Mood Provenance & Calibration**
   - Model predictions remain immutable in `EmotionResult` while user reviews (*Yes* / *Not quite* / *Skip* / *None fits* and *How did you feel then?*) are stored separately in `MoodReview`.
   - Conversation breakdowns independently track trajectory shift fit and proposed-context agreement with explicit denominators.
   - Once at least 5 non-skipped journal reviews accumulate, an on-device **personalization calibration profile** (`PersonalPatternProfile`) surfaces gentle tailored reading hints and reorders correction choices without altering raw model estimates.
4. **Transparent Consented Context ("What Sol Remembers")**
   - Periodic (~36h) gentle *"Everything alright? Anything on your mind?"* check-ins (`LifePulseController`), confirmed moments, and recurring confirmed shift contexts flow into companion LLM prompts **only when `ConsentKey.profileSnippet` / `ConsentKey.memoryMoments` are granted**, mirroring the exact text shown on *What Sol remembers*.

---

## Quickstart & Setup

### 1. Reproducible Offline Checks (No GPU or External Assets Required)

From the repository root, run the unified verification suite:

```powershell
python scripts/verify_release.py
```

This runs Dart consent-migration checks, `emotion_server` cue tests, `companion_server` unit/auth/HTTP tests, `flutter analyze`, and the full `flutter test` suite. Pass `--skip-flutter-tests` for a fast check of analyzer + Dart/Python suites.

To run component suites individually:

```powershell
# 1) Emotion consent migration checks
dart scripts/verify_emotion_consent.dart

# 2) Companion server unit, prompt, safety, journal API, and auth tests
cd companion_server
python -m pytest test_memory_prompt.py test_turn_detector.py test_session_logic.py test_conversation_memory.py test_tts_chunker.py test_journal_api.py test_auth_service.py test_auth_http.py

# 3) Reference emotion cue tests
cd ..\emotion_server
python -m unittest discover -s . -p "test_cue.py" -v

# 4) Flutter static analysis & widget/domain tests
cd ..\mobile_application
flutter analyze
flutter test
```

### 2. Mobile Application (`mobile_application/`)

- **SDK**: Flutter (Dart SDK `^3.8.1`), Android target (`com.sysmentalhealth.solace_mobile`).
- **Offline mode**: `flutter pub get` and `flutter run` (or `flutter build apk --debug`).
- **Live Firebase Authentication** *(external configuration required)*:
  Register `com.sysmentalhealth.solace_mobile` in Firebase Console (Email/Password & Google providers + SHA fingerprints) and place your downloaded `google-services.json` into `mobile_application/android/app/`. Do **not** commit credentials. See [mobile_application/README.md](mobile_application/README.md).

### 3. Companion Server (`companion_server/`)

- Install dependencies (`pip install -r companion_server/requirements.txt`).
- Configure Firebase Auth (`SOLACE_AUTH_MODE=firebase`, `SOLACE_FIREBASE_PROJECT_ID`, and host `GOOGLE_APPLICATION_CREDENTIALS`) or explicit loopback Firebase Auth Emulator (`SOLACE_AUTH_MODE=emulator`).
- Start with `python -m uvicorn main:app --host 127.0.0.1 --port 8000` (behind TLS for non-local use) and verify `/healthz`. See [companion_server/README.md](companion_server/README.md).

### 4. Reference Emotion Backend (`emotion_server/`)

- Install runtime bounds (`pip install -r emotion_server/requirements.txt`) inside an isolated environment.
- Supply `SOLACE_EMOTION_MODELS_DIR` and `SOLACE_EMOTION_ARTIFACTS_DIR`, verify artifact integrity with `python emotion_server/check_assets.py --verify-hashes [--face]`, and run on localhost (`python -m uvicorn emotion_api:app --host 127.0.0.1 --port 8766`). See [emotion_server/README.md](emotion_server/README.md) and [emotion_server/evaluation/README.md](emotion_server/evaluation/README.md) for MELD baseline limits.

---

## Testing & Verification Boundaries

Automated verification in this repository uses fake/mock identity boundaries and model-free harnesses for deterministic CI/offline reproducibility. The following **cannot** be attested by offline unit tests alone and remain explicit release/evaluation boundaries:

- Live device sign-in and Google credential exchange against a configured Firebase project (`google-services.json`).
- Live end-to-end GPU model loading, capture-to-result latency, and quantized inference inside `emotion_server/` and `companion_server/`.
- Ethically approved target-user human evaluation of longitudinal retention, usability, and qualitative personalization benefit (see [publication/README.md](publication/README.md)).

---

## License & Citation

Source code created in this repository is licensed under the [MIT License](LICENSE). Third-party pretrained model backbones and external assets remain under their respective upstream licenses.

If referencing this software, please cite it using [CITATION.cff](CITATION.cff).
