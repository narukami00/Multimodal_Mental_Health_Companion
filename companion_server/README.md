# Solace companion server

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
