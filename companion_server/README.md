# Solace companion server

## Authentication and owner-bound sessions

The companion now requires Firebase Authentication. The self-care app can continue storing journals and self-care activity locally without signing in; remote chat, calls, journal analysis and model downloads require an identity token. There is no anonymous or static `local-auth-token` fallback.

Production configuration (PowerShell):

```powershell
$env:SOLACE_AUTH_MODE = 'firebase' # default; never accepts emulator tokens
$env:SOLACE_FIREBASE_PROJECT_ID = 'your-project-id'
# Supply Application Default Credentials through the hosting identity, or an external
# GOOGLE_APPLICATION_CREDENTIALS file. Never commit credentials or put them in the app.
python -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Install `firebase-admin` from requirements. Production identity checks use the Admin SDK with revocation/disabled-account checks enabled. Missing project configuration stops startup; missing credentials, unavailable verification or SDK dependencies fail closed. Never set `FIREBASE_AUTH_EMULATOR_HOST` in production: the server refuses that combination. Use HTTPS/WSS with a trusted certificate for network deployment, put this server behind a correctly configured TLS proxy, and keep inference service ports private. HTTP over an external network would expose bearer credentials; authentication does not encrypt transport.

Every `/v1/*` HTTP call must carry `Authorization: Bearer <Firebase ID token>` in its header. This includes model manifests/downloads, `/v1/models`, `/v1/voices`, session creation and every journal upload. `/healthz` is public for diagnostics and reports model availability; it no longer exposes the server recording-directory path. CORS is disabled for browser origins by default; set comma-separated exact `SOLACE_CORS_ORIGINS` if a browser client is intentionally supported. Wildcards are ignored.

1. `POST /v1/sessions` with `{ "purpose": "chat" }` or `{ "purpose": "journal" }` returns `{ "session_id": "...", "ws_url": "/ws/v1/session", "expires_at": 1234567890 }`. `expires_at` is UNIX epoch seconds. Legacy client/thread/capability metadata is accepted for compatibility but confers no authority. The response contains no reusable session token.
2. Native Flutter chat/call transport connects to `/ws/v1/session?session_id=...` with the Firebase bearer token in the **WebSocket handshake Authorization header**. Video uses `/ws/v1/video?session_id=...` with the same header and chat session ID. Query-string `token`, `access_token` and `id_token` fields are rejected. Browser WebSocket clients that cannot set headers are not supported by this authentication transport.
3. Journal text, audio, camera frames and face vectors all use a server-issued `purpose=journal` session ID and bearer headers. A client-generated local journal ID remains local; it is not an authorization credential. All uploads must use the same issued ID for that entry. Another account, an unknown ID, an expired lease or a chat-purpose ID is refused before inference.

Leases are bound to the verified Firebase UID and purpose, use cryptographically random IDs, and expire at the earlier of one hour or the issuing token's expiry. One chat transport is allowed per issued chat ID (duplicate connection: close 4409); reconnect after disconnect while the lease remains valid, or issue a fresh ID. WebSockets close at token/lease expiry (4401). Ownership/purpose denial closes 4403. Refresh the Firebase ID token before expiry and issue a new lease as needed. A token refresh does not extend an existing lease. Video also stops accepting frames once its parent live call ends, in addition to the existing per-frame camera-consent checks.

### Explicit offline development authentication

Use the Firebase Authentication Emulator rather than bypassing identity verification:

```powershell
$env:SOLACE_AUTH_MODE = 'emulator'
$env:SOLACE_FIREBASE_PROJECT_ID = 'demo-solace-local'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099' # host:port, no scheme
# Start the Auth emulator separately and configure the Flutter debug app to use it.
python -m uvicorn main:app --host 127.0.0.1 --port 8000
```

The project IDs in emulator client and server must match. Emulator mode is deliberately insecure for identity minting, requires a loopback emulator address, and must only run locally with test identities/data. It requires no production service credentials and never substitutes an unverified production token. There is no network-free static bearer mode; core auth logic can be tested without any SDK or network using injected fakes.

```powershell
python -m unittest discover -s . -p 'test_auth_*.py' -v
```

`test_auth_service.py` runs with the standard library. `test_auth_http.py` adds real FastAPI HTTP/WebSocket route tests using fake identity verification and fake models; it requires FastAPI/httpx and explicitly skips when they are unavailable. The existing journal inference tests inject an explicit test authorizer. No test mode is activated by production environment variables.

Current boundaries: leases are in memory and single-process (restart loses them; multiple workers need a shared session store). Revocation is checked when verifying each request/handshake; an already open socket is not continuously reverified and is bounded by its expiry. This is identity/ownership enforcement, not a complete public-service deployment: rate limits, deployment TLS, operational monitoring, Firebase account-deletion coordination and independent security review still require configuration. The companion's ephemeral inference state does not synchronize app journals to Firebase or change local storage ownership.

Local speech-to-text, language model and text-to-speech behind one WebSocket
(`/ws/v1/session`), serving the app's text chat, push-to-talk voice and live calls.

```
run_companion_server.bat          # or: python -m uvicorn main:app --host 0.0.0.0 --port 8000
curl http://127.0.0.1:8000/healthz
```

`/healthz` shows where each model actually runs. **Check it first when a call
feels slow**: `stt_device` and `llm_device` should say `cuda` on a machine with an
NVIDIA card.

## Setup

```
pip install -r requirements.txt
pip install nvidia-cublas-cu12 "nvidia-cudnn-cu12<10"     # GPU: Whisper ~10x, LLM first token ~10x
```

The cuBLAS / cuDNN libraries are found automatically (`cuda_libs.py`). If they were
installed elsewhere, point `SOLACE_CUDA_LIBS` at the folder that contains `nvidia/`.

The first start converts the language model to CTranslate2 int8 (about 30 s, once).
It is stored under `models/llm/`.

## Settings (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `SOLACE_TTS` | `auto` | `auto`, `piper`, `kokoro`, `edge`, `mock`. `auto` uses local Kokoro/Piper weights when present, otherwise the cloud Edge voice. |
| `SOLACE_ESPEAK_DATA` | `models/tts/espeak-ng-data` | The espeak-ng data folder local voices need. |
| `SOLACE_LLM_MODEL` | `Qwen/Qwen2.5-0.5B-Instruct` | Any Qwen2 / Llama-style chat model. A 1.5B model is affordable on a GPU. |
| `SOLACE_LLM_BACKEND` | `auto` | `hf` forces the slower Transformers path. |
| `SOLACE_WHISPER_MODEL` | `base.en` | Any faster-whisper model name. |
| `SOLACE_DEBUG_RECORDINGS` | `0` | `1` writes each turn's audio to `debug_recordings/`. |

## How a live call works

```
phone                                   server
  call.listen ───────────────────────►  Silero VAD (own model instance per call)
  20 ms mic frames, always, ─────────►  TurnDetector: speech onset / end of turn
                                         │  turn.started, turn.speech_detected
                                         │  turn.endpointed        (650 ms of silence)
                                         ▼
                                        Whisper ──► transcript_final
                                         │          (an unfinished sentence waits 0.7 s
                                         ▼           for its continuation)
                                        LLM tokens ─► llm_chunk ... llm_done
                                         │
                                         ▼  clause by clause, next one synthesised
                                        TTS ───────► tts.start / segment / PCM / end
  ◄───────────────────────────────────  turn.latency  (where the time went)
```

* The **phone never decides** where a turn starts or ends. It streams the
  microphone and plays what it is sent. On a loudspeaker it sends silence while
  Sol is audible (her own voice would come back in); on headphones the mic stays
  open and speaking over Sol interrupts her (`call.config`).
* `turn.latency` and the `LATENCY ...` log line break each turn into
  speech-to-text, first LLM token and text-to-speech time.
* History records what the person *heard*: an interrupted reply is truncated to
  the clauses that were played, and a reply they never heard leaves only their own
  words, which merge into what they say next.

Messages the app sends for a call: `session.configure`, `call.listen`, `call.mute`,
`call.config`, `call.barge_in`, `turn.interrupted`, `call.end`. Explicit
`input.start` / `input.end` and `audio_start` / `audio_end` turns remain for
push-to-talk voice messages in chat.

## Tests

```
python -m pytest test_turn_detector.py test_session_logic.py     # fast, no models, no server
python -m pytest test_conversation_memory.py test_memory_prompt.py test_tts_chunker.py
# need the server running (set SOLACE_SERVER=host:port if it is not on 127.0.0.1:8000):
python -m pytest test_call_stream.py test_duplex_turn.py test_phase3_vad_stt.py test_audio_stream.py
```

`test_call_stream.py` streams real recorded speech and room noise at real-time pace,
the way the phone does, and prints the measured latency.

## Choosing the voice

The cloud Edge voice sounds good but needs the internet and costs 1.3-2.9 s per
clause. Local Piper costs about 0.15-0.4 s. To use it, place the model files in
`models/tts/` (`en_US-amy-low.onnx`, `tokens.txt`) and the espeak-ng data folder
beside them, then start with `SOLACE_TTS=piper`.
