"""One WebSocket connection: protocol, turn-taking and the reply pipeline.

Who decides what
----------------
* Live call: the phone streams the microphone continuously (`call.listen`). The
  server's Silero VAD finds where each person-turn starts and ends
  (`turn_detector.TurnDetector`), transcribes it once, and answers. The phone no
  longer guesses from volume, so a quiet voice, a noisy room or the assistant's
  own speaker cannot open, hold open or cut a turn.
* Reply pipeline: LLM tokens -> sentence chunker -> TTS, with the next clause
  being synthesised while the current one is sent, so there is no gap between
  clauses and the transcript never waits for the audio.
* History: a turn is recorded when it ends - complete, or truncated to what the
  person actually heard if they interrupted it.

The explicit `input.start` / `input.end` and `audio_start` / `audio_end` turns
(push-to-talk voice messages in chat, and the integration tests) keep working.
"""

from __future__ import annotations

import asyncio
from emotion_client import EmotionClient, default_client
import json
import logging
import os
import re
import struct
import threading
import time
import wave
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Awaitable, Callable, Deque, Dict, List, Optional, Tuple
from uuid import uuid4

from fastapi import WebSocket, WebSocketDisconnect

import safety_gate
from conversation_memory import clean_summary, sanitize_resume, sanitize_turns
from llm_service import LlmService, sanitize_memory
from moment_extraction import clean_context
from stt_service import VAD_WINDOW, SttService, StreamingVad
from text_chunker import TextChunker
from tts_engine import BaseTtsEngine
from tts_text import normalize_for_speech
from turn_detector import TurnDetector

logger = logging.getLogger("solace_companion.session")

# Per-turn WAV dumps. Off by default: they are written off the event loop, but
# they still grow without bound.
DEBUG_RECORDINGS = os.environ.get("SOLACE_DEBUG_RECORDINGS", "0") == "1"
RECORDINGS_DIR = Path(__file__).resolve().parent / "debug_recordings"

# Client -> server tunables. A `session.configure` `vad` block overrides these;
# unknown keys are ignored and the server always wins.
DEFAULT_VAD_CONFIG: Dict[str, Any] = {
    "provider": "silero",
    "threshold": 0.5,
    "neg_threshold": 0.35,
    "min_speech_ms": 128,         # speech this long opens a turn
    "min_turn_speech_ms": 250,    # a turn with less is a cough or a knock
    "endpoint_ms": 650,           # silence this long ends a turn
    "max_speech_ms": 30000,       # no turn may run longer
    "pre_roll_ms": 600,           # audio kept from before the onset
    "speech_pad_ms": 200,         # audio kept around the speech edges
    "barge_in_confirm_ms": 350,   # speech this long interrupts the assistant
    "merge_window_ms": 2500,      # a pause inside a thought is not a new turn
    "carry_hold_ms": 700,         # extra wait when a sentence sounds unfinished
}
_LEGACY_VAD_KEYS = {"min_silence_ms": "endpoint_ms"}

FRAME_HEADER = struct.Struct("<II")  # uint32 stream_id, uint32 sequence
FACE_SERVER_ENABLED = os.environ.get("SOLACE_EMOTION_FACE") == "1"  # camera frames are refused unless this server switch is on
LIVE_SESSIONS: Dict[str, "Session"] = {}  # session id -> its newest connection (the video socket finds its session here)
LOG_TEXT = os.environ.get("SOLACE_LOG_TEXT") == "1"  # development only: the user's words are not written to the log otherwise


def _logged(text: str) -> str:
    """What may appear in a log line for a piece of user text: its size, unless text logging was switched on for development."""
    return f'"{text}"' if LOG_TEXT else f"<{len(text.split())} words>"
TTS_FRAME_MS = 100
INTER_CLAUSE_PAUSE_MS = 80  # for a clause that does not end in punctuation
# The breath after a clause depends on how it ended, as in the voice sample the user chose: short at a comma, longer at a full stop.
CLAUSE_PAUSE_MS = {",": 160, ";": 220, ":": 200, ".": 360, "!": 360, "?": 400}
DEFAULT_VOICE_ID = "af_bella"  # Kokoro's Bella, chosen by ear from the samples
DEFAULT_VOICE_SPEED = 1.0
TTS_PREFETCH = 2               # clauses synthesised ahead of the one being sent
CLIENT_PLAYBACK_LAG_MS = 250   # arrival at the phone -> sound from the speaker
VOICE_MAX_TOKENS = 80
CHAT_MAX_TOKENS = 120
LISTEN_SAMPLE_RATE = 16000

_TERMINAL_PUNCTUATION = ".?!\"')”’"
_TRAILING_CONTINUATION = (",", ";", ":", "-", "—", "…", "...")
_CONNECTOR_WORDS = {
    "and", "but", "so", "because", "or", "then", "like", "um", "uh", "umm", "uhh",
    "the", "a", "an", "to", "of", "that", "if", "when", "with", "my", "as", "for", "about",
}


class CallPhase(str, Enum):
    """Server-authoritative call state."""

    IDLE = "idle"
    USER_SPEAKING = "user_speaking"
    THINKING = "thinking"
    ASSISTANT_SPEAKING = "assistant_speaking"
    MUTED = "muted"
    ENDED = "ended"


def looks_incomplete(text: str) -> bool:
    """True when a transcript sounds like the person has more to say.

    Only strong signals count: a trailing comma, dash or ellipsis, or a sentence
    that stops on a connecting word with no punctuation after it. A missing full
    stop alone is not one - Whisper often leaves it off a finished short reply -
    and waiting on every such turn would add latency to a quarter of them.
    """
    t = text.strip()
    if not t:
        return False
    if t.endswith(_TRAILING_CONTINUATION):
        return True
    if t[-1] in _TERMINAL_PUNCTUATION:
        return False
    words = re.findall(r"[a-z']+", t.lower())
    return bool(words) and words[-1] in _CONNECTOR_WORDS


@dataclass
class Reply:
    """One assistant response in flight: generation, synthesis and bookkeeping."""

    user_turn_id: str
    user_text: str
    spoken: bool  # a live call: short, speakable sentences
    voice_turn: bool = False
    turn_id: str = field(default_factory=lambda: f"asst_{uuid4().hex[:8]}")
    utterance_id: str = field(default_factory=lambda: f"utt_{uuid4().hex[:8]}")
    audio_stream_id: Optional[int] = None
    task: Optional["asyncio.Task[None]"] = None
    tts_task: Optional["asyncio.Task[None]"] = None
    llm_cancel: threading.Event = field(default_factory=threading.Event)
    tts_cancel: asyncio.Event = field(default_factory=asyncio.Event)
    # [text, start_ms, end_ms] per synthesised clause on the playback timeline.
    segments: List[List[Any]] = field(default_factory=list)
    sent_ms: int = 0
    first_audio_at: Optional[float] = None
    audible_until: float = 0.0
    truncate_to_ms: Optional[int] = None
    generated: str = ""
    history_done: bool = False
    committed_index: Optional[int] = None  # position of the user message in history
    tts_end_sent: bool = False
    cancel_notified: bool = False
    finished: bool = False
    cancel_reason: Optional[str] = None
    t_start: float = field(default_factory=time.monotonic)
    t_user_stopped: Optional[float] = None
    stt_ms: Optional[int] = None
    t_first_token: Optional[float] = None
    emotion_cue: str = ""  # optional hedged tone note for this reply (see emotion_client.py); empty = none
    fixed_text: str = ""  # safety: when set, this exact text is the reply and the language model is not called


@dataclass
class ListenTurn:
    turn_id: str
    base_sample: int
    audio: bytearray
    speech_start_sample: int
    opened_at: float = field(default_factory=time.monotonic)
    overlapped_assistant: bool = False  # began while Sol was audible: the audio may hold her voice, so it is not analysed for emotion


class Listener:
    """The continuous microphone stream of a live call."""

    def __init__(
        self,
        vad: StreamingVad,
        detector: TurnDetector,
        sample_rate: int,
        pre_roll_ms: int,
        pad_ms: int,
        barge_in: bool,
        base_min_speech_ms: int,
        barge_in_confirm_ms: int,
    ) -> None:
        self.vad = vad
        self.detector = detector
        self.sample_rate = sample_rate
        self.pad_samples = pad_ms * sample_rate // 1000
        self.ring_samples = max(pre_roll_ms, pad_ms) * sample_rate // 1000
        self.barge_in = barge_in
        self.base_min_speech_ms = base_min_speech_ms
        self.barge_in_confirm_ms = barge_in_confirm_ms
        self.muted = False
        self.turn: Optional[ListenTurn] = None
        self.ring = bytearray()
        self.ring_start_sample = 0
        self.total_samples = 0
        self.expected_seq: Optional[int] = None
        self.frame_gaps = 0
        self.turn_counter = 0
        # Global sample index of detector window 0: the VAD restarts on clear().
        self.window_origin = 0

    def window_start_sample(self, window: int) -> int:
        return self.window_origin + window * VAD_WINDOW

    def push_audio(self, pcm: bytes) -> None:
        self.ring += pcm
        self.total_samples += len(pcm) // 2
        overflow = len(self.ring) // 2 - self.ring_samples
        if overflow > 0:
            del self.ring[: overflow * 2]
            self.ring_start_sample += overflow

    def clear(self) -> None:
        """Forget the open turn and every buffered sample (mute, barge-in reset)."""
        self.turn = None
        self.ring.clear()
        self.ring_start_sample = self.total_samples
        self.window_origin = self.total_samples
        self.detector.reset()
        self.vad.reset()

    def next_turn_id(self) -> str:
        self.turn_counter += 1
        return f"srv_{self.turn_counter}_{uuid4().hex[:4]}"


class Session:
    """State and behaviour of a single client connection."""

    def __init__(
        self,
        websocket: WebSocket,
        stt: SttService,
        llm: LlmService,
        tts: BaseTtsEngine,
        session_id: Optional[str] = None,
        emotion: Optional[EmotionClient] = None,
    ) -> None:
        self.ws = websocket
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.session_id = session_id or f"sess_{uuid4().hex[:8]}"
        # Optional emotion service (audio + text -> a hedged tone note). Off unless SOLACE_EMOTION=1 AND the app opts in with
        # session.configure {"emotion": {"enabled": true}}. Any failure means 'no cue': a call never depends on it.
        self.emotion = emotion if emotion is not None else default_client()
        self._pending_cue = ""  # the cue computed for the turn that is about to be answered (also covers continuation holds)
        self._safety_cooldown = 0  # turns left after an urgent one in which no emotion cue is sent
        self._emotion_audio: Dict[str, "asyncio.Task[bool]"] = {}  # turn_id -> the upload of that turn's audio to the service

        self.history: List[Dict[str, str]] = []
        self.vad_config: Dict[str, Any] = dict(DEFAULT_VAD_CONFIG)
        self.config: Dict[str, Any] = {
            "mode": "chat_voice_playback",
            "tts_enabled": True,
            "voice_id": DEFAULT_VOICE_ID,
            "speed": DEFAULT_VOICE_SPEED,
            "mic_sample_rate": 16000,
            "playback_sample_rate": tts.default_sample_rate,
            "codec": "pcm_s16le",
            "emotion": False,
            "emotion_face": False,
        }
        self.phase = CallPhase.IDLE
        self._stream_ids = iter(range(2001, 1 << 31))
        self._closed = False

        self.listener: Optional[Listener] = None
        # Bumped whenever a call starts or ends: work begun for an earlier call
        # (a turn still being transcribed) must not answer into the next one.
        self._call_gen = 0
        self.reply: Optional[Reply] = None
        self._stt_lock = asyncio.Lock()
        self._tasks: set[asyncio.Task] = set()

        # A finished-sounding user turn waits briefly for a continuation.
        self._carry_text: Optional[str] = None
        self._carry_task: Optional[asyncio.Task] = None
        # The user's words when their reply never reached their ears.
        self._unanswered: Optional[Tuple[str, float]] = None

        # Explicit (client-delimited) turns: push-to-talk voice and the tests.
        self._audio_turns: Dict[str, Dict[str, Any]] = {}
        self._current_audio_turn_id: Optional[str] = None
        self._explicit_duplex = False

        self._handlers: Dict[str, Callable[[Dict[str, Any]], Awaitable[None]]] = {
            "hello": self._h_hello,
            "session.configure": self._h_configure,
            "moment.extract": self._h_moment_extract,
            "summary.request": self._h_summary_request,
            "speech.cancel": self._h_speech_cancel,
            "call.barge_in": self._h_call_barge_in,
            "turn.interrupted": self._h_turn_interrupted,
            "turn.cancel": self._h_turn_cancel,
            "call.listen": self._h_call_listen,
            "call.mute": self._h_call_mute,
            "call.config": self._h_call_config,
            "call.end": self._h_call_end,
            "ping": self._h_ping,
            "text_message": self._h_text_message,
            "audio_start": self._h_input_start,
            "input.start": self._h_input_start,
            "audio_end": self._h_input_end,
            "input.end": self._h_input_end,
            "audio_cancel": self._h_audio_cancel,
        }

    # ------------------------------------------------------------------ plumbing

    async def run(self) -> None:
        """Serve the connection until the client leaves."""
        await self.ws.accept()
        LIVE_SESSIONS[self.session_id] = self  # a reconnect with the same id replaces the old connection
        logger.info(f"WebSocket client connected. Session ID: {self.session_id}")
        try:
            while True:
                message = await self.ws.receive()
                if message.get("type") == "websocket.disconnect":
                    raise WebSocketDisconnect(message.get("code", 1000))
                if message.get("bytes") is not None:
                    await self._on_binary(message["bytes"])
                elif message.get("text") is not None:
                    await self._on_text(message["text"])
        except WebSocketDisconnect:
            logger.info(f"WebSocket client disconnected cleanly: session {self.session_id}")
        except Exception as e:
            logger.error(f"WebSocket connection error: {e}", exc_info=True)
        finally:
            await self._shutdown()

    async def _shutdown(self) -> None:
        self._closed = True
        if LIVE_SESSIONS.get(self.session_id) is self:
            del LIVE_SESSIONS[self.session_id]
        reply = self.reply
        if reply is not None:
            self._stop_generation(reply, tts=True, llm=True, reason="disconnect")
        if self._carry_task is not None:
            self._carry_task.cancel()
        for task in list(self._tasks):
            task.cancel()
        self.listener = None
        if self.config.get("emotion"):  # forget this session's smoothing state; fire and forget, never blocks the shutdown
            asyncio.ensure_future(self.emotion.reset(self.session_id))

    # ------------------------------------------------------------------- emotion cue (optional)

    def _emotion_on(self) -> bool:
        return bool(self.config.get("emotion")) and self.emotion.usable

    def face_allowed(self) -> bool:
        """Camera frames are accepted only with the server switch, the app's emotion opt-in AND its separate face consent."""
        return FACE_SERVER_ENABLED and bool(self.config.get("emotion")) and bool(self.config.get("emotion_face"))

    async def video_frame(self, jpeg: bytes) -> Dict[str, Any]:
        """One upright JPEG frame from the video socket. Refused (never decoded) without consent; otherwise the face numbers are
        computed by the emotion service and kept there in memory. Returns {'usable': 0/1/None} or {'refused': reason}."""
        if not self.face_allowed():
            return {"refused": "no_consent"}
        if not self.emotion.usable:
            return {"usable": None}
        res = await self.emotion.frame(self.session_id, time.monotonic(), jpeg)
        return {"usable": None if not res or not res.get("accepted") else res.get("usable")}

    async def _emotion_cue(self, turn_id: str, text: str, use_audio: bool, face_window: Optional[Tuple[float, float]] = None) -> str:
        """Ask the emotion service about this turn and return the hedged cue ('' = none).

        Bounded by the client's timeout, never raises. Also tells an opted-in app what was inferred (`emotion.update`).
        (Crisis language is NOT handled here: `safety_gate` in `_start_reply` is independent of this service.)"""
        upload = self._emotion_audio.pop(turn_id, None)
        if not self._emotion_on():
            return ""
        try:
            if use_audio:
                # Make the order deterministic: the audio upload must have reached the service before the result is requested,
                # otherwise the service could answer from the text alone. The upload is tiny (local) and has run beside the STT.
                accepted = False
                if upload is not None:
                    try:
                        accepted = bool(await asyncio.wait_for(asyncio.shield(upload), 1.5))
                    except Exception:
                        accepted = False
                extra = {"face_window": list(face_window)} if face_window and self.face_allowed() else {}
                res = await self.emotion.finalize(self.session_id, turn_id, text, use_audio=accepted, **extra)
            else:
                res = await self.emotion.text(self.session_id, text)
        except Exception as e:  # the client already swallows errors; this is belt and braces
            logger.warning(f"emotion cue failed: {e}")
            return ""
        if not res or not res.get("decision"):
            return ""
        d, cue = res["decision"], res.get("cue") or ""
        est = res.get("estimate") or {}
        update = {
            "type": "emotion.update", "turn_id": turn_id, "source": "voice" if use_audio else "text",
            "model_version": res.get("model_version"), "pattern": d.get("pattern"), "mood": d.get("mood"), "tier": d.get("tier"),
            "valence": d.get("valence"), "arousal": d.get("arousal"), "cue_used": bool(cue), "suppressed": d.get("suppressed"),
            "estimate": {"lv": est.get("lv"), "la": est.get("la"), "l7": est.get("l7")},
        }
        face = res.get("face")
        if face and self.face_allowed():
            # The face on its own, only for the person's optional "how you looked" view. It never shapes the reply.
            update["face"] = {"lv": face.get("lv"), "la": face.get("la"), "l7": face.get("l7")}
        await self._send(update)
        return cue  # crisis language is handled by safety_gate in _start_reply, not here

    def _spawn(self, coro: Awaitable[None]) -> "asyncio.Task[None]":
        task = asyncio.ensure_future(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        task.add_done_callback(self._log_task_failure)
        return task

    @staticmethod
    def _log_task_failure(task: "asyncio.Task[Any]") -> None:
        if task.cancelled():
            return
        err = task.exception()
        if err is not None:
            logger.error(f"Background task failed: {err!r}", exc_info=err)

    async def _send(self, payload: Dict[str, Any]) -> None:
        if self._closed:
            return
        payload.setdefault("v", 1)
        payload.setdefault("session_id", self.session_id)
        payload.setdefault("ts", int(time.time() * 1000))
        try:
            await self.ws.send_text(json.dumps(payload))
        except Exception as e:
            self._closed = True
            logger.debug(f"send failed ({payload.get('type')}): {e}")

    async def _send_bytes(self, data: bytes) -> bool:
        if self._closed:
            return False
        try:
            await self.ws.send_bytes(data)
            return True
        except Exception as e:
            self._closed = True
            logger.debug(f"binary send failed: {e}")
            return False

    @property
    def _call_context(self) -> bool:
        return self.listener is not None or self._explicit_duplex

    async def _set_phase(self, new_phase: CallPhase, reason: str, force: bool = False) -> None:
        """Emit `call.state` on every transition. Only calls have a state to show."""
        if self.phase == new_phase and not force:
            return
        if not self._call_context and new_phase != CallPhase.ENDED:
            return  # a text chat has no call state to track or announce
        logger.info(f"call.state {self.phase.value} -> {new_phase.value} ({reason})")
        self.phase = new_phase
        await self._send({
            "type": "call.state",
            "state": new_phase.value,
            "phase": new_phase.value,
            "reason": reason,
        })

    def _next_stream_id(self) -> int:
        return next(self._stream_ids)

    async def _on_text(self, raw: str) -> None:
        try:
            data = json.loads(raw)
        except Exception as e:
            logger.warning(f"Invalid JSON received: {e}")
            await self._send({
                "type": "error", "code": "invalid_json",
                "message": "Payload must be valid JSON", "retryable": False,
            })
            return
        msg_type = data.get("type")
        handler = self._handlers.get(msg_type)
        if handler is None:
            logger.warning(f"Unknown message type: {msg_type}")
            await self._send({
                "type": "error", "code": "unknown_type",
                "message": f"Unsupported message type: {msg_type}", "retryable": False,
            })
            return
        await handler(data)

    # ------------------------------------------------------------ simple messages

    async def _h_hello(self, data: Dict[str, Any]) -> None:
        self.session_id = data.get("session_id") or self.session_id
        logger.info(
            f"Received 'hello' for session {self.session_id}, "
            f"thread: {data.get('thread_id', 'thread_default')}"
        )
        await self._send({
            "type": "session_ready",
            "server_time": int(time.time() * 1000),
            "state": "idle",
            "tts": self._tts_info(),
        })

    def _tts_info(self) -> Dict[str, Any]:
        return {
            "enabled": self.config["tts_enabled"],
            "engine": self.tts.name,
            "voice_id": self.config["voice_id"],
            "sample_rate": self.tts.default_sample_rate,
        }

    async def _h_configure(self, data: Dict[str, Any]) -> None:
        self.config["mode"] = data.get("mode", self.config["mode"])
        if isinstance(data.get("country"), str) and data["country"].strip():
            self.config["country"] = data["country"].strip().upper()[:2]  # selects the local crisis resources; absent = default (BD)
        # The person's own consented memory block. Authoritative on every
        # configure: absent means none, so withdrawing consent takes effect on
        # the next configure. Held for this connection only, never logged.
        self.config["memory"] = sanitize_memory(data.get("memory"))
        # Resuming a conversation: a summary of older turns plus the last few
        # verbatim. History is seeded only when this connection has none.
        resume = sanitize_resume(data.get("resume"))
        if resume:
            self.config["summary"] = resume["summary"]
            if not self.history:
                self.history.extend(resume["recent"])

        tts_opts = data.get("tts", {})
        if isinstance(tts_opts, dict):
            if "enabled" in tts_opts:
                self.config["tts_enabled"] = bool(tts_opts["enabled"])
            if "voice_id" in tts_opts:
                self.config["voice_id"] = str(tts_opts["voice_id"])
            if "speed" in tts_opts:
                self.config["speed"] = float(tts_opts["speed"])
        audio_opts = data.get("audio", {})
        if isinstance(audio_opts, dict):
            if "mic_sample_rate" in audio_opts:
                self.config["mic_sample_rate"] = int(audio_opts["mic_sample_rate"])
            if "playback_sample_rate" in audio_opts:
                self.config["playback_sample_rate"] = int(audio_opts["playback_sample_rate"])
            if "codec" in audio_opts:
                self.config["codec"] = str(audio_opts["codec"])

        vad_opts = data.get("vad", {})
        if isinstance(vad_opts, dict):
            for legacy, current in _LEGACY_VAD_KEYS.items():
                if legacy in vad_opts and current not in vad_opts:
                    vad_opts = {**vad_opts, current: vad_opts[legacy]}
            for key, default in DEFAULT_VAD_CONFIG.items():
                if key not in vad_opts:
                    continue
                try:
                    self.vad_config[key] = type(default)(vad_opts[key])
                except (TypeError, ValueError):
                    logger.warning(f"Ignoring invalid vad.{key}={vad_opts[key]!r}")
            self.stt.vad_threshold = float(self.vad_config["threshold"])
            self.stt.vad_neg_threshold = float(self.vad_config["neg_threshold"])
            self.stt.vad_min_speech_ms = int(self.vad_config["min_speech_ms"])
            logger.info(f"Session VAD config: {self.vad_config}")

        ready: Dict[str, Any] = {
            "type": "session.ready",
            "mode": self.config["mode"],
            "tts": self._tts_info(),
            "vad": self.vad_config,
        }
        emotion_opts = data.get("emotion")
        if isinstance(emotion_opts, dict):
            # Opt-in per session (consent is the app's call); effective only if the service is switched on server-side.
            self.config["emotion"] = bool(emotion_opts.get("enabled")) and self.emotion.enabled
            # The camera is a SEPARATE consent: the app says so explicitly, and the server must have it switched on too.
            self.config["emotion_face"] = bool(emotion_opts.get("face_features")) and FACE_SERVER_ENABLED
            ready["emotion"] = {"enabled": self.config["emotion"], "server_enabled": self.emotion.enabled,
                               "face": self.face_allowed()}
        await self._send(ready)

    async def _h_ping(self, data: Dict[str, Any]) -> None:
        await self._send({
            "type": "pong",
            "client_ts": data.get("ts", int(time.time() * 1000)),
            "server_time": int(time.time() * 1000),
        })

    async def _h_moment_extract(self, data: Dict[str, Any]) -> None:
        request_id = str(data.get("request_id", ""))[:64]
        text = data.get("text")
        text = text if isinstance(text, str) else ""
        context = clean_context(data.get("context"))

        async def _extract() -> None:
            moment = await self.llm.extract_moment_async(text, context)
            await self._send({"type": "moment.proposal", "request_id": request_id, "text": moment})

        self._spawn(_extract())

    async def _h_summary_request(self, data: Dict[str, Any]) -> None:
        request_id = str(data.get("request_id", ""))[:64]
        previous = clean_summary(data.get("previous_summary"))
        turns = sanitize_turns(data.get("messages"), max_turns=40)

        async def _summarize() -> None:
            result = await self.llm.summarize_async(previous, turns)
            await self._send({
                "type": "summary.result",
                "request_id": request_id,
                "summary": result["summary"],
                "method": result["method"],
            })

        self._spawn(_summarize())

    # -------------------------------------------------------------- cancellation

    async def _h_speech_cancel(self, data: Dict[str, Any]) -> None:
        """Chat mute / stop voice: silence the audio, optionally the text too."""
        cancel_tts = bool(data.get("cancel_tts", True))
        cancel_llm = bool(data.get("cancel_llm", False))
        reason = data.get("reason", "user_cancelled")
        logger.info(f"Speech cancel: tts={cancel_tts}, llm={cancel_llm}, reason={reason}")
        reply = self.reply
        if reply is None:
            return
        self._stop_generation(reply, tts=cancel_tts, llm=cancel_llm, reason=reason)
        if cancel_llm:
            self._settle_cancelled(reply, explicit=False)
        if cancel_tts:
            await self._notify_tts_cancelled(reply, reason)

    async def _h_call_barge_in(self, data: Dict[str, Any]) -> None:
        """Stop everything now. The truncation-aware sibling is `turn.interrupted`."""
        reason = data.get("reason", "barge_in")
        logger.info(f"Call barge-in: turn={data.get('turn_id')}, reason={reason}")
        reply = self.reply
        if reply is not None:
            self._stop_generation(reply, tts=True, llm=True, reason=reason)
            self._settle_cancelled(reply, explicit=False)
        self._drop_open_explicit_turns()
        await self._send({"type": "call.state", "state": "listening", "reason": reason})
        if reply is not None:
            await self._notify_tts_cancelled(reply, reason)

    async def _h_turn_interrupted(self, data: Dict[str, Any]) -> None:
        """The client interrupted: it reports exactly how much the person heard."""
        played_ms = int(data.get("played_ms", 0))
        logger.info(
            f"turn.interrupted [{data.get('turn_id')}] played_ms={played_ms} "
            f"assistant={data.get('interrupted_turn_id') or (self.reply.turn_id if self.reply else None)}"
        )
        reply = self.reply
        if reply is not None:
            reply.truncate_to_ms = played_ms
            self._stop_generation(reply, tts=True, llm=True, reason="user_speech")
            self._settle_cancelled(reply, explicit=True)
        self._drop_open_explicit_turns()
        if reply is not None:
            await self._notify_tts_cancelled(reply, "user_speech")
        await self._set_phase(CallPhase.USER_SPEAKING, "client_interrupted")

    async def _h_turn_cancel(self, data: Dict[str, Any]) -> None:
        """The client abandoned a turn (mute, page disposed, call end)."""
        turn_id = data.get("turn_id") or self._current_audio_turn_id
        reason = data.get("reason", "client_cancelled")
        logger.info(f"turn.cancel [{turn_id}] reason={reason}")
        if turn_id:
            self._close_audio_turn(turn_id)
            await self._send({"type": "turn.discarded", "turn_id": turn_id, "reason": "cancelled"})
        # Cancelling a turn while the assistant speaks must not claim the floor is free.
        if self.phase in (CallPhase.IDLE, CallPhase.THINKING):
            await self._set_phase(CallPhase.IDLE, reason)

    async def _h_audio_cancel(self, data: Dict[str, Any]) -> None:
        turn_id = data.get("turn_id") or self._current_audio_turn_id or "turn_unknown"
        reason = data.get("reason", "user_cancelled")
        logger.info(f"Audio cancel for turn {turn_id}, reason: {reason}")
        reply = self.reply
        if reply is not None:
            self._stop_generation(reply, tts=True, llm=True, reason=reason)
            self._settle_cancelled(reply, explicit=False)
            await self._notify_tts_cancelled(reply, reason)
        self._close_audio_turn(turn_id)
        await self._send({"type": "turn_cancelled", "turn_id": turn_id, "reason": reason})

    async def _h_call_end(self, data: Dict[str, Any]) -> None:
        reply = self.reply
        if reply is not None:
            self._stop_generation(reply, tts=True, llm=True, reason="call_ended")
            self._settle_cancelled(reply, explicit=False)
        self._cancel_carry()
        self._drop_open_explicit_turns()
        self.listener = None
        self._call_gen += 1
        self._explicit_duplex = False
        self._unanswered = None
        self.config["mode"] = "chat_voice_playback"
        await self._set_phase(CallPhase.ENDED, "call_ended")

    # ------------------------------------------------------------------- text chat

    async def _h_text_message(self, data: Dict[str, Any]) -> None:
        turn_id = data.get("turn_id", f"turn_{uuid4().hex[:6]}")
        user_text = data.get("text", "")
        logger.info(f"Received text message [{turn_id}]: {_logged(user_text)}")
        await self._send({"type": "echo", "turn_id": turn_id, "text": f"Echo: {user_text}"})
        if user_text.strip():
            cue = await self._emotion_cue(turn_id, user_text.strip(), use_audio=False)
            await self._start_reply(user_turn_id=turn_id, text=user_text.strip(),
                                    spoken=False, voice_turn=False, emotion_cue=cue)

    # ------------------------------------------------------- continuous call stream

    async def _h_call_listen(self, data: Dict[str, Any]) -> None:
        """Start listening to the live microphone stream."""
        sample_rate = int(data.get("sample_rate", LISTEN_SAMPLE_RATE))
        if sample_rate != LISTEN_SAMPLE_RATE:
            await self._send({
                "type": "error", "code": "unsupported_sample_rate",
                "message": f"call.listen needs {LISTEN_SAMPLE_RATE} Hz audio", "retryable": False,
            })
            return
        cfg = self.vad_config
        previous = self.reply
        if previous is not None:
            # A new call starts clean: nothing from the last one may still be talking.
            self._stop_generation(previous, tts=True, llm=True, reason="new_call")
            self._settle_cancelled(previous, explicit=False)
            await self._notify_tts_cancelled(previous, "new_call")
        self._call_gen += 1
        vad = await asyncio.to_thread(self.stt.new_streaming_vad, sample_rate, False)
        vad.threshold = float(cfg["threshold"])
        vad.neg_threshold = float(cfg["neg_threshold"])
        detector = TurnDetector(
            threshold=float(cfg["threshold"]),
            neg_threshold=float(cfg["neg_threshold"]),
            min_speech_ms=int(cfg["min_speech_ms"]),
            endpoint_ms=int(cfg["endpoint_ms"]),
            min_turn_speech_ms=int(cfg["min_turn_speech_ms"]),
            max_turn_ms=int(cfg["max_speech_ms"]),
        )
        self.listener = Listener(
            vad=vad,
            detector=detector,
            sample_rate=sample_rate,
            pre_roll_ms=int(cfg["pre_roll_ms"]),
            pad_ms=int(cfg["speech_pad_ms"]),
            barge_in=bool(data.get("barge_in", False)),
            base_min_speech_ms=int(cfg["min_speech_ms"]),
            barge_in_confirm_ms=int(cfg["barge_in_confirm_ms"]),
        )
        self.config["mode"] = "duplex_call"
        self._cancel_carry()
        self._unanswered = None
        logger.info(
            f"Listening: sr={sample_rate}, barge_in={self.listener.barge_in}, "
            f"endpoint={cfg['endpoint_ms']}ms"
        )
        await self._set_phase(CallPhase.IDLE, "listening", force=True)
        await self._send({
            "type": "call.listening",
            "sample_rate": sample_rate,
            "barge_in": self.listener.barge_in,
            "endpoint_ms": int(cfg["endpoint_ms"]),
        })

    async def _h_call_mute(self, data: Dict[str, Any]) -> None:
        listener = self.listener
        muted = bool(data.get("muted", True))
        if listener is None:
            return
        listener.muted = muted
        if muted:
            dropped = listener.turn
            listener.clear()
            self._cancel_carry()
            if dropped is not None:
                await self._send({
                    "type": "turn.discarded", "turn_id": dropped.turn_id, "reason": "cancelled",
                })
            if self.phase in (CallPhase.USER_SPEAKING, CallPhase.THINKING):
                await self._set_phase(CallPhase.IDLE, "muted")
        else:
            listener.clear()

    async def _h_call_config(self, data: Dict[str, Any]) -> None:
        """Change a live call's settings: voice interruption follows the audio route
        (headphones leave no echo, a speakerphone does)."""
        listener = self.listener
        if listener is None or "barge_in" not in data:
            return
        listener.barge_in = bool(data["barge_in"])
        logger.info(f"Call barge_in -> {listener.barge_in}")
        await self._send({"type": "call.listening", "barge_in": listener.barge_in,
                          "sample_rate": listener.sample_rate,
                          "endpoint_ms": int(self.vad_config["endpoint_ms"])})

    def _assistant_audible(self) -> bool:
        reply = self.reply
        return reply is not None and time.monotonic() < reply.audible_until

    async def _on_binary(self, payload: bytes) -> None:
        if self.listener is not None:
            await self._on_listen_frame(payload)
        else:
            await self._on_explicit_frame(payload)

    async def _on_listen_frame(self, raw: bytes) -> None:
        listener = self.listener
        if listener is None:
            return
        if len(raw) <= FRAME_HEADER.size:
            return
        _stream_id, seq = FRAME_HEADER.unpack(raw[: FRAME_HEADER.size])
        pcm = raw[FRAME_HEADER.size:]
        expected = listener.expected_seq
        if expected is not None and seq != expected:
            missing = max(1, seq - expected if seq > expected else 1)
            listener.frame_gaps += missing
            await self._send({
                "type": "turn.diagnostic", "reason": "frame_gap",
                "expected": expected, "received": seq, "missing": missing,
            })
        listener.expected_seq = seq + 1
        if listener.muted:
            return

        listener.push_audio(pcm)
        # While the assistant is audible an interruption must outlast a longer
        # run of speech than an ordinary onset.
        listener.detector.min_speech_ms = (
            listener.barge_in_confirm_ms
            if listener.barge_in and self._assistant_audible()
            else listener.base_min_speech_ms
        )
        listener.vad.push(pcm)
        probs = list(listener.vad.window_probs)

        started_now = False
        for prob in probs:
            for event in listener.detector.push(prob):
                if event.kind == "speech_start":
                    started_now = await self._on_speech_start(event, prob)
                elif event.kind == "speech_end":
                    await self._on_speech_end(event)
                elif event.kind == "discard":
                    await self._on_discard(event)
        if listener.turn is not None and not started_now:
            listener.turn.audio += pcm

    async def _on_speech_start(self, event, prob: float) -> bool:
        listener = self.listener
        if listener is None:
            return False
        audible = self._assistant_audible()
        if audible and not listener.barge_in:
            # The assistant's own voice leaking back is not a person speaking.
            listener.detector.reset(keep_clock=True)
            return False

        start_sample = listener.window_start_sample(event.window)
        base = max(listener.ring_start_sample, start_sample - listener.pad_samples)
        audio = bytearray(listener.ring[(base - listener.ring_start_sample) * 2:])
        turn_id = listener.next_turn_id()
        listener.turn = ListenTurn(
            turn_id=turn_id, base_sample=base, audio=audio, speech_start_sample=start_sample,
            overlapped_assistant=audible,
        )
        if audible:
            await self._barge_in("user_speech")
        # Anything still waiting on a continuation belongs to this new utterance.
        self._pause_carry()
        offset_ms = int(start_sample / listener.sample_rate * 1000)
        await self._send({
            "type": "turn.started", "turn_id": turn_id,
            "sample_rate": listener.sample_rate, "frame_ms": 20,
            "pre_roll_ms": int(self.vad_config["pre_roll_ms"]),
            "threshold": self.vad_config["threshold"],
            "neg_threshold": self.vad_config["neg_threshold"],
        })
        await self._send({
            "type": "turn.speech_detected", "turn_id": turn_id, "offset_ms": offset_ms,
            "speech_start_sample": start_sample, "confidence": round(prob, 3),
            "source": "server_vad",
        })
        await self._set_phase(CallPhase.USER_SPEAKING, "server_vad")
        return True

    async def _on_speech_end(self, event) -> None:
        listener = self.listener
        if listener is None:
            return
        turn = listener.turn
        listener.turn = None
        if turn is None:
            return
        speech_end_sample = listener.window_start_sample(event.window + 1)
        end_sample = speech_end_sample + listener.pad_samples
        cut = max(0, min(len(turn.audio), (end_sample - turn.base_sample) * 2))
        pcm = bytes(turn.audio[:cut])
        total_ms = int(len(turn.audio) / 2 / listener.sample_rate * 1000)
        stopped_at = time.monotonic() - event.silence_ms / 1000.0
        await self._send({
            "type": "turn.endpointed", "turn_id": turn.turn_id, "reason": event.reason,
            "speech_end_sample": speech_end_sample,
            "speech_ms": event.speech_ms, "silence_ms": event.silence_ms,
            "total_ms": total_ms, "deadline_ms": int(self.vad_config["endpoint_ms"]),
            "frame_gaps": listener.frame_gaps,
        })
        await self._set_phase(CallPhase.THINKING, "endpointed")
        if DEBUG_RECORDINGS:
            self._dump_wav(turn.turn_id, pcm, listener.sample_rate)
        self._spawn(self._process_listen_turn(
            turn.turn_id, pcm, listener.sample_rate, event.speech_ms,
            stopped_at, event.reason == "max_duration", self._call_gen, turn.overlapped_assistant,
            (turn.opened_at - 1.0, stopped_at + 0.5),  # the camera frames that belong to this turn
        ))

    async def _on_discard(self, event) -> None:
        listener = self.listener
        if listener is None:
            return
        turn = listener.turn
        listener.turn = None
        if turn is None:
            return
        await self._send({
            "type": "turn.discarded", "turn_id": turn.turn_id, "reason": event.reason,
            "speech_ms": event.speech_ms,
        })
        await self._after_empty_turn(event.reason)

    async def _after_empty_turn(self, reason: str) -> None:
        """A turn produced nothing to answer: hand the floor back, or finish a
        reply that was only waiting to see whether the person would continue."""
        if self._carry_text is not None:
            await self._release_carry()
            return
        if self._assistant_audible():
            await self._set_phase(CallPhase.ASSISTANT_SPEAKING, reason)
        else:
            await self._set_phase(CallPhase.IDLE, reason)

    async def _process_listen_turn(
        self,
        turn_id: str,
        pcm: bytes,
        sample_rate: int,
        speech_ms: int,
        stopped_at: float,
        forced: bool,
        call_gen: int,
        overlapped_assistant: bool = False,
        face_window: Optional[Tuple[float, float]] = None,
    ) -> None:
        """Transcribe one endpointed turn, then answer it."""
        if self._emotion_on() and not overlapped_assistant and sample_rate and len(pcm) >= 2 * sample_rate // 3:
            # Start the audio features NOW so they are ready by the time the transcript is (runs beside the speech-to-text).
            self._emotion_audio[turn_id] = self._spawn(self.emotion.start_audio(self.session_id, turn_id, pcm, sample_rate))
        async with self._stt_lock:
            if self._closed or call_gen != self._call_gen:
                self._emotion_audio.pop(turn_id, None)
                return
            await self._send({"type": "turn.processing", "turn_id": turn_id,
                              "stage": "stt", "elapsed_ms": 0})
            t0 = time.monotonic()
            try:
                text, confidence, language = await asyncio.to_thread(
                    self.stt.transcribe_pcm, pcm, sample_rate, speech_ms
                )
            except Exception as e:
                logger.error(f"Transcription failed for {turn_id}: {e}", exc_info=True)
                text, confidence, language = "", 0.0, "en"
            stt_ms = int((time.monotonic() - t0) * 1000)

        if self._closed or call_gen != self._call_gen:
            return  # the call ended while this was being transcribed
        if not text:
            self._emotion_audio.pop(turn_id, None)
            logger.info(f"Discarding turn {turn_id}: unintelligible")
            await self._send({"type": "transcript_failed", "turn_id": turn_id,
                              "reason": "unintelligible", "confidence": round(confidence, 2)})
            await self._send({"type": "turn.discarded", "turn_id": turn_id,
                              "reason": "unintelligible", "speech_ms": speech_ms,
                              "confidence": round(confidence, 2)})
            await self._after_empty_turn("unintelligible")
            return

        logger.info(f"Transcribed turn {turn_id}: {_logged(text)} (conf={confidence:.2f}, stt={stt_ms}ms)")
        await self._send({
            "type": "transcript_final", "turn_id": turn_id, "text": text, "stable": True,
            "language": language, "confidence": round(confidence, 2),
            "audio_ms": int(len(pcm) / 2 / sample_rate * 1000),
        })
        self._pending_cue = await self._emotion_cue(turn_id, text, use_audio=True, face_window=face_window)

        # A thought continued after a pause is one turn, not two.
        if self._carry_text:
            text = f"{self._carry_text} {text}"
            self._cancel_carry()
        elif self._unanswered is not None:
            earlier, at = self._unanswered
            if (time.monotonic() - at) * 1000 <= int(self.vad_config["merge_window_ms"]):
                text = f"{earlier} {text}"
            self._unanswered = None

        if looks_incomplete(text) and not forced and self.listener is not None:
            self._hold_for_continuation(turn_id, text, stopped_at, stt_ms)
            return
        await self._start_reply(
            user_turn_id=turn_id, text=text, spoken=True, voice_turn=True,
            t_user_stopped=stopped_at, stt_ms=stt_ms,
        )

    # ---- continuation hold

    def _hold_for_continuation(self, turn_id: str, text: str, stopped_at: float, stt_ms: int) -> None:
        """The sentence sounds unfinished: wait a moment before answering it."""
        self._cancel_carry()
        self._carry_text = text
        hold_s = int(self.vad_config["carry_hold_ms"]) / 1000.0
        logger.info(f"Holding unfinished turn {turn_id} for {hold_s:.1f}s: {_logged(text)}")
        self._carry_task = self._spawn(self._carry_timeout(turn_id, hold_s, stopped_at, stt_ms))

    async def _carry_timeout(self, turn_id: str, hold_s: float, stopped_at: float, stt_ms: int) -> None:
        await asyncio.sleep(hold_s)
        text = self._carry_text
        self._carry_text = None
        self._carry_task = None
        if text:
            await self._start_reply(
                user_turn_id=turn_id, text=text, spoken=True, voice_turn=True,
                t_user_stopped=stopped_at, stt_ms=stt_ms,
            )

    def _pause_carry(self) -> None:
        """New speech began: stop the timer, keep the words for the continuation."""
        if self._carry_task is not None:
            self._carry_task.cancel()
            self._carry_task = None

    def _cancel_carry(self) -> None:
        self._pause_carry()
        self._carry_text = None

    async def _release_carry(self) -> None:
        """The continuation never came (it was noise): answer what we held."""
        text = self._carry_text
        self._carry_text = None
        if text:
            await self._start_reply(
                user_turn_id=f"carry_{uuid4().hex[:6]}", text=text, spoken=True, voice_turn=True,
                t_user_stopped=time.monotonic(),
            )

    # ------------------------------------------------------------ explicit turns

    async def _h_input_start(self, data: Dict[str, Any]) -> None:
        """Client-delimited turn: the client says when it starts and ends."""
        is_duplex = data.get("type") == "input.start"
        turn_id = data.get("turn_id") or data.get("input_id") or f"turn_{uuid4().hex[:6]}"
        sample_rate = int(data.get("sample_rate", 16000))
        channels = int(data.get("channels", 1))
        frame_ms = int(data.get("frame_ms", 20 if is_duplex else 100))
        encoding = data.get("encoding") or data.get("codec") or "pcm16"
        is_framed = is_duplex or bool(data.get("framed", False))

        vad = None
        if is_duplex:
            vad = await asyncio.to_thread(self.stt.new_streaming_vad, sample_rate, True)
        self._audio_turns[turn_id] = {
            "turn_id": turn_id, "sample_rate": sample_rate, "channels": channels,
            "frame_ms": frame_ms, "encoding": encoding, "is_framed": is_framed,
            "chunks": [], "total_bytes": 0, "frame_count": 0, "start_time": time.time(),
            "expected_seq": None, "stream_id": None, "frame_gaps": 0,
            "speech_reported": False, "vad": vad,
        }
        # Always take over: close any stale turn so new audio reaches this one.
        if self._current_audio_turn_id is not None and self._current_audio_turn_id != turn_id:
            stale = self._current_audio_turn_id
            self._close_audio_turn(stale)
            logger.info(f"Closed stale turn {stale} for new turn {turn_id}")
        self._current_audio_turn_id = turn_id
        logger.info(
            f"Turn started: {turn_id} (sr={sample_rate}, ch={channels}, frame_ms={frame_ms}, "
            f"framed={is_framed}, open_turns={len(self._audio_turns)})"
        )
        if is_duplex:
            self._explicit_duplex = True
            await self._send({
                "type": "turn.started", "turn_id": turn_id, "sample_rate": sample_rate,
                "frame_ms": frame_ms,
                "pre_roll_ms": int(data.get("pre_roll_ms", self.vad_config["pre_roll_ms"])),
                "threshold": self.vad_config["threshold"],
                "neg_threshold": self.vad_config["neg_threshold"],
            })
            await self._set_phase(CallPhase.USER_SPEAKING, "input_start")
        await self._send({"type": "audio_ack", "turn_id": turn_id, "status": "ready_for_frames"})

    async def _on_explicit_frame(self, audio_bytes: bytes) -> None:
        turn = self._audio_turns.get(self._current_audio_turn_id or "")
        if turn is None:
            logger.warning(f"Rejected binary frame ({len(audio_bytes)} B): no open turn")
            await self._send({"type": "turn.diagnostic", "reason": "frame_no_turn",
                              "bytes": len(audio_bytes)})
            return
        payload = audio_bytes
        if turn["is_framed"]:
            if len(audio_bytes) <= FRAME_HEADER.size:
                await self._send({"type": "turn.diagnostic", "turn_id": turn["turn_id"],
                                  "reason": "frame_too_short", "bytes": len(audio_bytes)})
                return
            stream_id, seq = FRAME_HEADER.unpack(audio_bytes[: FRAME_HEADER.size])
            payload = audio_bytes[FRAME_HEADER.size:]
            expected = turn["expected_seq"]
            if expected is not None and seq != expected:
                missing = seq - expected if seq > expected else 1
                turn["frame_gaps"] += max(1, missing)
                logger.warning(f"Frame gap on {turn['turn_id']}: expected {expected}, got {seq}")
                await self._send({
                    "type": "turn.diagnostic", "turn_id": turn["turn_id"], "reason": "frame_gap",
                    "expected": expected, "received": seq, "missing": max(1, missing),
                })
            turn["expected_seq"] = seq + 1
            turn["stream_id"] = stream_id

        turn["chunks"].append(payload)
        turn["total_bytes"] += len(payload)
        turn["frame_count"] += 1

        # Streaming VAD: the low-latency speech-onset signal, no transcript needed.
        vad = turn.get("vad")
        if vad is not None:
            prob = vad.push(payload)
            if vad.ever_spoke and not turn["speech_reported"]:
                turn["speech_reported"] = True
                await self._send({
                    "type": "turn.speech_detected", "turn_id": turn["turn_id"],
                    "offset_ms": int(turn["total_bytes"] / (turn["sample_rate"] * 2) * 1000),
                    "speech_start_sample": vad.speech_start_sample,
                    "confidence": round(prob, 3), "source": "server_vad",
                })
                await self._set_phase(CallPhase.USER_SPEAKING, "server_vad")

    async def _h_input_end(self, data: Dict[str, Any]) -> None:
        """End of a client-delimited turn: transcribe once, then answer."""
        turn_id = data.get("turn_id") or data.get("input_id") or self._current_audio_turn_id or "turn_unknown"
        is_duplex = data.get("type") == "input.end"
        logger.info(f"Turn end received for {turn_id}")

        turn = self._audio_turns.get(turn_id)
        if not turn or not turn["chunks"]:
            logger.warning(f"Turn end for {turn_id} with no buffered frames")
            await self._send({"type": "audio_received", "turn_id": turn_id, "frames": 0,
                              "bytes": 0, "duration_ms": 0, "wav_file": None})
            if turn_id in self._audio_turns:
                self._close_audio_turn(turn_id)
                await self._send({"type": "turn.discarded", "turn_id": turn_id, "reason": "silence"})
                await self._set_phase(CallPhase.IDLE, "no_audio")
            return

        raw_pcm = b"".join(turn["chunks"])
        sr, ch = turn["sample_rate"], turn["channels"]
        duration_sec = len(raw_pcm) / (sr * ch * 2) if sr * ch * 2 > 0 else 0.0
        vad = turn.get("vad")
        probabilities = vad.probabilities if vad is not None else None
        speech_ms = vad.speech_ms if vad is not None else 0
        silence_ms = int(vad.silence_samples / sr * 1000) if vad is not None else 0
        last_speech_sample = vad.last_speech_sample if vad else -1
        frame_gaps, frame_count = turn["frame_gaps"], turn["frame_count"]
        self._close_audio_turn(turn_id)

        wav_name = self._dump_wav(turn_id, raw_pcm, sr) if DEBUG_RECORDINGS else None
        await self._send({
            "type": "audio_received", "turn_id": turn_id, "frames": frame_count,
            "bytes": len(raw_pcm), "duration_ms": int(duration_sec * 1000),
            "wav_file": wav_name, "frame_gaps": frame_gaps,
        })
        if is_duplex:
            await self._send({
                "type": "turn.endpointed", "turn_id": turn_id,
                "reason": data.get("reason", "silence"),
                "speech_end_sample": last_speech_sample, "speech_ms": speech_ms,
                "silence_ms": silence_ms, "total_ms": int(duration_sec * 1000),
                "deadline_ms": int(self.vad_config["endpoint_ms"]), "frame_gaps": frame_gaps,
            })
            await self._set_phase(CallPhase.THINKING, "endpointed")
            await self._send({"type": "turn.processing", "turn_id": turn_id,
                              "stage": "stt", "elapsed_ms": 0})

        if self._emotion_on() and ch == 1 and sr and len(raw_pcm) >= 2 * sr // 3:
            self._emotion_audio[turn_id] = self._spawn(self.emotion.start_audio(self.session_id, turn_id, raw_pcm, sr))  # runs beside the STT
        async with self._stt_lock:
            t0 = time.monotonic()
            text, confidence, language, _eot, vad_speech_ms = await asyncio.to_thread(
                self.stt.analyze, raw_pcm, sr, probabilities
            )
            stt_ms = int((time.monotonic() - t0) * 1000)

        if not text:
            self._emotion_audio.pop(turn_id, None)
            reason = "silence" if not (probabilities or vad_speech_ms) else "unintelligible"
            logger.info(f"Discarding turn {turn_id}: {reason}")
            await self._send({"type": "transcript_failed", "turn_id": turn_id,
                              "reason": reason, "confidence": round(confidence, 2)})
            if is_duplex:
                await self._send({"type": "turn.discarded", "turn_id": turn_id, "reason": reason,
                                  "speech_ms": vad_speech_ms, "confidence": round(confidence, 2)})
                await self._set_phase(CallPhase.IDLE, reason)
            return

        logger.info(f"Transcribed turn {turn_id}: {_logged(text)} (conf={confidence:.2f}, lang={language})")
        await self._send({
            "type": "transcript_final", "turn_id": turn_id, "text": text, "stable": True,
            "language": language, "confidence": round(confidence, 2),
            "audio_ms": int(duration_sec * 1000),
        })
        cue = await self._emotion_cue(turn_id, text, use_audio=(ch == 1))
        await self._start_reply(
            user_turn_id=turn_id, text=text, spoken=is_duplex, voice_turn=True,
            t_user_stopped=time.monotonic(), stt_ms=stt_ms, emotion_cue=cue,
        )
        if is_duplex:
            await self._set_phase(CallPhase.THINKING, "transcript_final")

    def _close_audio_turn(self, turn_id: str) -> None:
        """Free a turn's buffers. Called on end, cancel and interrupt so a barge-in
        race can never orphan a chunk list for the life of the connection."""
        self._audio_turns.pop(turn_id, None)
        if self._current_audio_turn_id == turn_id:
            self._current_audio_turn_id = next(iter(self._audio_turns), None)

    def _drop_open_explicit_turns(self) -> None:
        for turn_id in list(self._audio_turns):
            self._close_audio_turn(turn_id)

    def _dump_wav(self, turn_id: str, pcm: bytes, sample_rate: int) -> Optional[str]:
        """Write a debug WAV on a worker thread; never on the event loop."""
        RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
        name = f"{turn_id}_{int(time.time())}.wav"
        path = RECORDINGS_DIR / name

        def _write() -> None:
            try:
                with wave.open(str(path), "wb") as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)
                    wf.setframerate(sample_rate)
                    wf.writeframes(pcm)
            except Exception as err:
                logger.error(f"Failed to write WAV {path}: {err}")

        threading.Thread(target=_write, daemon=True).start()
        return name

    # ------------------------------------------------------------ reply pipeline

    async def _start_reply(
        self,
        user_turn_id: str,
        text: str,
        spoken: bool,
        voice_turn: bool,
        t_user_stopped: Optional[float] = None,
        stt_ms: Optional[int] = None,
        emotion_cue: Optional[str] = None,
    ) -> None:
        """Begin answering [text], superseding any answer still in flight.

        [emotion_cue]: the optional hedged tone note for this reply; None = use the cue computed for the most recent voice turn
        (this also covers an unfinished sentence that was held and is answered later)."""
        cue = emotion_cue if emotion_cue is not None else self._pending_cue
        self._pending_cue = ""
        # Safety gate: the one place every answered text passes (typed, spoken, merged or held). It does not depend on the
        # emotion service, and it never reads an emotion estimate.
        level = safety_gate.assess(text)
        fixed_text = ""
        if level == safety_gate.URGENT:
            self._safety_cooldown = safety_gate.COOLDOWN_TURNS
            fixed_text = safety_gate.crisis_reply(self.config.get("country"), spoken=spoken)
        if level or self._safety_cooldown > 0:
            cue = ""
            if level != safety_gate.URGENT and self._safety_cooldown > 0:
                self._safety_cooldown -= 1
        if level:
            logger.warning(f"Safety gate: {level} on turn {user_turn_id}")  # level only, never the words
            await self._send({"type": "safety.alert", "level": level, "turn_id": user_turn_id})
        previous = self.reply
        if previous is not None and (
            not previous.finished or time.monotonic() < previous.audible_until
        ):
            self._stop_generation(previous, tts=True, llm=True, reason="superseded")
            self._settle_cancelled(previous, explicit=False)
            await self._notify_tts_cancelled(previous, "superseded_by_new_turn")

        reply = Reply(user_turn_id=user_turn_id, user_text=text, spoken=spoken,
                      voice_turn=voice_turn, t_user_stopped=t_user_stopped, stt_ms=stt_ms, emotion_cue=cue or "",
                      fixed_text=fixed_text)
        self.reply = reply
        if spoken:
            self._unanswered = (text, time.monotonic())
        reply.task = asyncio.ensure_future(self._run_reply(reply))
        self._tasks.add(reply.task)
        reply.task.add_done_callback(self._tasks.discard)
        reply.task.add_done_callback(self._log_task_failure)

    async def _reply_stream(self, reply: Reply, messages: List[Dict[str, str]], max_tokens: int):
        """The reply text as a stream: the fixed safety text when the gate set one, else the language model."""
        if reply.fixed_text:
            yield reply.fixed_text
            return
        async for chunk in self.llm.generate_stream_async(messages, max_new_tokens=max_tokens, cancel=reply.llm_cancel):
            yield chunk

    async def _run_reply(self, reply: Reply) -> None:
        cfg = self.config
        call_mode = cfg.get("mode") == "duplex_call"
        engine = self.tts
        synthesize = bool(
            (cfg.get("tts_enabled", True) or call_mode or reply.voice_turn)
            and engine is not None and engine.is_ready
        )
        voice_id = cfg.get("voice_id", DEFAULT_VOICE_ID)
        speed = float(cfg.get("speed", DEFAULT_VOICE_SPEED))
        sample_rate = engine.default_sample_rate if engine else 24000
        if synthesize:
            reply.audio_stream_id = self._next_stream_id()

        extra = {"emotion_cue": reply.emotion_cue} if reply.emotion_cue else {}  # only when there is a cue: older LLM stand-ins keep working
        if reply.emotion_cue:
            logger.info(f"Emotion cue attached to reply {reply.turn_id} ({len(reply.emotion_cue)} chars)")  # never log the cue text
        messages = [] if reply.fixed_text else self.llm.build_messages(  # a fixed safety reply never reaches the language model
            reply.user_text,
            history=self.history,
            memory=cfg.get("memory"),
            summary=cfg.get("summary", ""),
            spoken=reply.spoken,
            **extra,
        )
        await self._send({
            "type": "llm_start", "turn_id": reply.turn_id, "utterance_id": reply.utterance_id,
            "audio_stream_id": reply.audio_stream_id, "reply_to": reply.user_turn_id,
            "model": self.llm.model_id, "prompt_tokens": len(reply.user_text.split()),
            # Diagnostic: lets a client (or a test) verify an interrupted turn was
            # recorded truncated rather than in full.
            "history_messages": len(self.history),
        })
        if synthesize and reply.audio_stream_id is not None:
            await self._send({
                "type": "tts.start", "turn_id": reply.turn_id, "utterance_id": reply.utterance_id,
                "audio_stream_id": reply.audio_stream_id, "codec": "pcm_s16le",
                "sample_rate": sample_rate, "channels": 1, "voice_id": voice_id,
            })

        queue: "asyncio.Queue[Optional[str]]" = asyncio.Queue()
        if synthesize and reply.audio_stream_id is not None:
            reply.tts_task = asyncio.ensure_future(
                self._tts_worker(reply, queue, engine, voice_id, speed, sample_rate)
            )
            self._tasks.add(reply.tts_task)
            reply.tts_task.add_done_callback(self._tasks.discard)

        chunker = TextChunker(is_call_mode=call_mode or reply.spoken)
        parts: List[str] = []
        max_tokens = VOICE_MAX_TOKENS if reply.spoken else CHAT_MAX_TOKENS
        try:
            async for chunk in self._reply_stream(reply, messages, max_tokens):
                if reply.t_first_token is None:
                    reply.t_first_token = time.monotonic()
                parts.append(chunk)
                await self._send({
                    "type": "llm_chunk", "turn_id": reply.turn_id,
                    "utterance_id": reply.utterance_id, "reply_to": reply.user_turn_id,
                    "delta": chunk,
                })
                if synthesize and not reply.tts_cancel.is_set():
                    for clause in chunker.add_token(chunk):
                        queue.put_nowait(clause)
        except asyncio.CancelledError:
            reply.finished = True
            logger.info(f"Reply {reply.turn_id} cancelled ({reply.cancel_reason})")
            raise
        except Exception as e:
            logger.error(f"Error during LLM streaming for {reply.turn_id}: {e}", exc_info=True)

        reply.generated = "".join(parts).strip()
        # Recorded as soon as the text is complete: the person has read or is
        # hearing it, and a follow-up must see it even while the audio is still
        # playing. An interruption amends it to what was actually heard.
        self._commit_history(reply, reply.generated)
        if synthesize and not reply.tts_cancel.is_set():
            remainder = chunker.flush()
            if remainder:
                queue.put_nowait(remainder)
        queue.put_nowait(None)

        total_ms = int((time.monotonic() - reply.t_start) * 1000)
        ttft_ms = int((reply.t_first_token - reply.t_start) * 1000) if reply.t_first_token else 0
        # The transcript is final now: it must not wait for the audio, and the
        # suggestion chips must not wait for a second model call.
        await self._send({
            "type": "llm_done", "turn_id": reply.turn_id, "utterance_id": reply.utterance_id,
            "reply_to": reply.user_turn_id, "text": reply.generated, "tokens": len(parts),
            "suggestions": []
            if reply.spoken
            else self.llm.fallback_suggestions(reply.generated, reply.user_text),
            "ttft_ms": ttft_ms, "duration_ms": total_ms,
            "latency_ms": {"ttft": ttft_ms, "total": total_ms},
        })
        logger.info(f"Completed LLM response for {reply.turn_id} ({len(parts)} chunks, {total_ms}ms, ttft={ttft_ms}ms)")

        if reply.tts_task is not None and not reply.tts_task.done():
            try:
                await reply.tts_task
            except asyncio.CancelledError:
                if reply.tts_cancel.is_set() and not reply.llm_cancel.is_set():
                    pass  # only the voice was cancelled; the text stands
                else:
                    raise
            except Exception as err:
                logger.error(f"Error awaiting TTS task: {err}")

        reply.finished = True
        if self.reply is reply and reply.spoken:
            self._spawn(self._idle_when_silent(reply))
        elif reply.spoken is False and self.phase == CallPhase.THINKING:
            await self._set_phase(CallPhase.IDLE, "llm_complete")

    async def _tts_worker(
        self,
        reply: Reply,
        queue: "asyncio.Queue[Optional[str]]",
        engine: BaseTtsEngine,
        voice_id: str,
        speed: float,
        sample_rate: int,
    ) -> None:
        """Synthesise clauses ahead of the one being sent and send them in order."""
        stream_id = reply.audio_stream_id
        assert stream_id is not None
        frame_bytes = int(sample_rate * 2 * TTS_FRAME_MS / 1000)
        inflight: Deque[Tuple[str, "asyncio.Future[Any]"]] = deque()
        seq = 0
        total_samples = 0
        timeline_ms = 0
        seg_idx = 0
        eof = False

        def synth(text: str) -> "asyncio.Future[Any]":
            return asyncio.ensure_future(
                # Numbers, taka and lakh, times and short forms are spelled out first; the text sent to the app is untouched.
                asyncio.to_thread(engine.synthesize, text=normalize_for_speech(text), voice_id=voice_id, speed=speed)
            )

        try:
            while True:
                # Keep the synthesiser busy: start the next clauses before the
                # current one has finished being sent.
                while not eof and len(inflight) < TTS_PREFETCH:
                    if inflight:
                        try:
                            item = queue.get_nowait()
                        except asyncio.QueueEmpty:
                            break
                    else:
                        item = await queue.get()
                    if item is None:
                        eof = True
                        break
                    inflight.append((item, synth(item)))
                if not inflight:
                    if eof:
                        break
                    continue

                text, future = inflight.popleft()
                result = await future
                if reply.tts_cancel.is_set():
                    break
                pcm = result.pcm_bytes
                if not pcm:
                    continue

                duration_ms = int(len(pcm) / (sample_rate * 2) * 1000)
                now = time.monotonic()
                if reply.first_audio_at is None:
                    reply.first_audio_at = now
                    reply.audible_until = now + CLIENT_PLAYBACK_LAG_MS / 1000.0
                    await self._set_phase(CallPhase.ASSISTANT_SPEAKING, "tts_first_segment")
                    await self._report_latency(reply, now)

                await self._send({
                    "type": "tts.segment", "turn_id": reply.turn_id,
                    "utterance_id": reply.utterance_id, "audio_stream_id": stream_id,
                    "segment_index": seg_idx, "text": text, "state": "started",
                    "sample_rate": sample_rate, "duration_ms": duration_ms,
                })
                total_samples += len(pcm) // 2
                reply.segments.append([text, timeline_ms, timeline_ms + duration_ms])
                timeline_ms += duration_ms
                reply.audible_until = max(reply.audible_until, now) + duration_ms / 1000.0

                for offset in range(0, len(pcm), frame_bytes):
                    if reply.tts_cancel.is_set():
                        break
                    ok = await self._send_bytes(
                        FRAME_HEADER.pack(stream_id, seq) + pcm[offset: offset + frame_bytes]
                    )
                    seq += 1
                    if not ok:
                        return
                    await asyncio.sleep(0)  # let heartbeats and microphone frames through

                if reply.tts_cancel.is_set():
                    break
                await self._send({
                    "type": "tts.segment", "turn_id": reply.turn_id,
                    "utterance_id": reply.utterance_id, "audio_stream_id": stream_id,
                    "segment_index": seg_idx, "state": "ended",
                })
                seg_idx += 1

                # A short breath between clauses, part of the playback timeline.
                pause_ms = CLAUSE_PAUSE_MS.get(text.rstrip()[-1:], INTER_CLAUSE_PAUSE_MS)
                pause_bytes = int(sample_rate * 2 * pause_ms / 1000) // 2 * 2
                await self._send_bytes(FRAME_HEADER.pack(stream_id, seq) + bytes(pause_bytes))
                seq += 1
                timeline_ms += pause_ms
                reply.sent_ms = timeline_ms
                reply.audible_until += pause_ms / 1000.0

            if not reply.tts_cancel.is_set():
                reply.tts_end_sent = True
                await self._send({
                    "type": "tts.end", "turn_id": reply.turn_id,
                    "utterance_id": reply.utterance_id, "audio_stream_id": stream_id,
                    "cancelled": False, "reason": "complete", "total_frames": seq,
                    "total_samples": total_samples,
                    "duration_ms": int(total_samples / sample_rate * 1000),
                })
        except asyncio.CancelledError:
            logger.info(f"TTS worker cancelled for {reply.utterance_id}")
            raise
        except Exception as e:
            logger.error(f"Error in TTS worker {reply.utterance_id}: {e}", exc_info=True)
        finally:
            # No tts.end here: the cancellation notice is sent by the canceller,
            # outside this task, where an await cannot be swallowed.
            for _text, future in inflight:
                future.cancel()

    async def _report_latency(self, reply: Reply, first_audio_at: float) -> None:
        """One line (and one event) that shows where a turn's time went."""
        if reply.t_user_stopped is None:
            return
        ttft = (reply.t_first_token - reply.t_start) * 1000 if reply.t_first_token else None
        report = {
            "type": "turn.latency", "turn_id": reply.user_turn_id,
            "reply_turn_id": reply.turn_id,
            "stt_ms": reply.stt_ms,
            "llm_first_token_ms": int(ttft) if ttft is not None else None,
            "tts_first_audio_ms": int((first_audio_at - (reply.t_first_token or reply.t_start)) * 1000),
            "to_first_audio_ms": int((first_audio_at - reply.t_user_stopped) * 1000),
        }
        logger.info(
            "LATENCY user stopped -> first audio %(to_first_audio_ms)s ms "
            "(stt %(stt_ms)s, llm first token %(llm_first_token_ms)s, "
            "tts after first token %(tts_first_audio_ms)s)" % report
        )
        await self._send(report)

    async def _idle_when_silent(self, reply: Reply) -> None:
        """Audio is sent faster than real time; return to idle once it has played."""
        remaining = reply.audible_until - time.monotonic()
        if remaining > 0:
            await asyncio.sleep(remaining)
        if self.reply is reply and self.phase == CallPhase.ASSISTANT_SPEAKING:
            await self._set_phase(CallPhase.IDLE, "tts_complete")

    # ---- cancellation and history

    def _stop_generation(self, reply: Reply, tts: bool, llm: bool, reason: str) -> None:
        """Signal the pipeline to stop. Never blocks and never raises."""
        reply.cancel_reason = reason
        if tts:
            reply.tts_cancel.set()
            if reply.tts_task is not None and not reply.tts_task.done():
                reply.tts_task.cancel()
        if llm:
            reply.llm_cancel.set()
            current = asyncio.current_task()
            if reply.task is not None and not reply.task.done() and reply.task is not current:
                reply.task.cancel()

    def _estimate_played_ms(self, reply: Reply) -> int:
        """How much of the reply has probably been heard, when the client has not said."""
        if reply.first_audio_at is None:
            return 0
        elapsed = (time.monotonic() - reply.first_audio_at) * 1000 - CLIENT_PLAYBACK_LAG_MS
        return int(max(0, min(elapsed, reply.sent_ms)))

    def _commit_history(self, reply: Reply, assistant_text: str) -> None:
        if reply.history_done:
            return
        reply.history_done = True
        reply.committed_index = len(self.history)
        self.history.append({"role": "user", "content": reply.user_text})
        self.history.append({"role": "assistant", "content": assistant_text})
        # The person has their answer: nothing is left waiting to be merged.
        self._unanswered = None

    def _settle_cancelled(self, reply: Reply, explicit: bool) -> None:
        """Decide what a cancelled reply leaves in the history.

        An interruption still happened, so a reply the person partly heard is
        recorded truncated to the clauses they heard. A reply they never heard
        leaves only their own words, which merge into what they say next.

        With a fast model the whole reply is usually generated, and recorded,
        long before it has been spoken; an interruption then amends the record
        instead of creating it.
        """
        reply.finished = True
        if not reply.spoken and not explicit:
            reply.history_done = True  # a chat message that was replaced: not recorded
            return
        playing = time.monotonic() < reply.audible_until
        if reply.history_done and not (explicit or playing):
            return  # already fully heard

        played = reply.truncate_to_ms
        if played is None:
            played = self._estimate_played_ms(reply)
        heard = [seg[0] for seg in reply.segments if seg[2] <= played]
        logger.info(
            f"Truncated {reply.turn_id} to played_ms={played} "
            f"({len(heard)}/{len(reply.segments)} clauses heard)"
        )
        heard_text = " ".join(heard).strip()

        if reply.history_done:
            index = reply.committed_index
            if index is None or index + 1 >= len(self.history):
                return
            if heard_text or explicit:
                self.history[index + 1]["content"] = heard_text
            else:
                # Never heard: drop the exchange and let the next utterance carry
                # the person's words forward.
                del self.history[index: index + 2]
                self._unanswered = (reply.user_text, time.monotonic())
            return

        if heard_text or explicit:
            self._commit_history(reply, heard_text)
        else:
            reply.history_done = True

    async def _notify_tts_cancelled(self, reply: Reply, reason: str) -> None:
        """Tell the client the audio stream is dead, from outside the dead task.

        A reply whose audio was already sent in full is still audible on the
        phone, so it is stopped there too until its estimated end.
        """
        if reply.audio_stream_id is None or reply.cancel_notified:
            return
        if reply.tts_end_sent and time.monotonic() >= reply.audible_until:
            return  # complete and already played out: nothing left to stop
        reply.cancel_notified = True
        reply.tts_end_sent = True
        await self._send({
            "type": "tts.end", "turn_id": reply.turn_id, "utterance_id": reply.utterance_id,
            "audio_stream_id": reply.audio_stream_id, "cancelled": True, "reason": reason,
        })

    async def _barge_in(self, reason: str) -> None:
        """The person spoke over the assistant (full-duplex clients only)."""
        reply = self.reply
        if reply is None:
            return
        played = self._estimate_played_ms(reply)
        self._stop_generation(reply, tts=True, llm=True, reason=reason)
        self._settle_cancelled(reply, explicit=False)
        logger.info(f"Barge-in on {reply.turn_id} at ~{played} ms")
        await self._notify_tts_cancelled(reply, reason)
        await self._send({
            "type": "turn.interrupted", "turn_id": reply.user_turn_id,
            "interrupted_turn_id": reply.turn_id, "played_ms": played,
            "reason": reason, "source": "server_vad",
        })
