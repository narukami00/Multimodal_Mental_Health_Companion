import asyncio
import json
import logging
import os
from enum import Enum
from pathlib import Path
import struct
import time
from typing import Any, Callable, Dict, List, Optional
from uuid import uuid4
import wave

from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from stt_service import SttService
from conversation_memory import sanitize_resume, sanitize_turns, clean_summary
from llm_service import LlmService, sanitize_memory
from text_chunker import TextChunker
from tts_engine import BaseTtsEngine, get_tts_engine, TtsAudioResult

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("solace_companion")

RECORDINGS_DIR = Path(__file__).resolve().parent / "debug_recordings"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)

# Per-turn WAV dumps. Off by default: the write used to run on the event loop for
# every turn, which blocked the heartbeat and grew without bound.
DEBUG_RECORDINGS = os.environ.get("SOLACE_DEBUG_RECORDINGS", "0") == "1"

# Client -> server tunable defaults (§5.11). A session.configure `vad` block
# overrides these; the server always wins over the client.
DEFAULT_VAD_CONFIG: Dict[str, Any] = {
    "provider": "silero",
    "threshold": 0.5,
    "neg_threshold": 0.35,
    "min_speech_ms": 120,
    "min_silence_ms": 700,
    "speech_pad_ms": 30,
    "max_speech_ms": 30000,
    "endpoint_min_ms": 500,
    "endpoint_max_ms": 1500,
    "endpoint_ema_alpha": 0.9,
    "pre_roll_ms": 600,
    "on_db_silent": 9.0,
    "on_db_speaking": 14.0,
    "off_db": 5.0,
    "barge_in_confirm_ms": 300,
    "barge_in_grace_ms": 700,
    "playback_cooldown_ms": 1500,
    "false_interruption_timeout_ms": 2000,
}


class CallPhase(str, Enum):
    """Server-authoritative call state (§7.4)."""

    IDLE = "idle"
    USER_SPEAKING = "user_speaking"
    THINKING = "thinking"
    ASSISTANT_SPEAKING = "assistant_speaking"
    MUTED = "muted"
    ENDED = "ended"


# Initialize STT, LLM and TTS services
stt = SttService(model_size="base.en")
llm = LlmService(model_id="Qwen/Qwen2.5-0.5B-Instruct")
tts = get_tts_engine(engine_type="auto")

app = FastAPI(
    title="Solace Companion Backend",
    version="0.1.0",
    description="Local mental health companion server supporting STT, LLM, TTS, and real-time WebSocket communication."
)

@app.on_event("startup")
async def on_startup():
    logger.info("Server startup: warming up STT, LLM & TTS services in background...")
    asyncio.create_task(asyncio.to_thread(stt.initialize))
    asyncio.create_task(asyncio.to_thread(llm.initialize))
    asyncio.create_task(asyncio.to_thread(tts.warmup))

# Enable CORS for local Flutter development (web, emulator, LAN)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory session registry for Phase 1
active_sessions: Dict[str, Dict[str, Any]] = {}

class CreateSessionRequest(BaseModel):
    client: str = Field(default="flutter-client", description="Client identifier/platform")
    thread_id: Optional[str] = Field(default=None, description="Thread or conversation ID")
    capabilities: Optional[Dict[str, bool]] = Field(
        default_factory=lambda: {"audio": True, "text": True, "emotion": True}
    )

class CreateSessionResponse(BaseModel):
    session_id: str
    ws_url: str
    token: str

@app.get("/healthz")
async def healthz():
    """Health check endpoint per specifications section 11 & Phase 6 TTS."""
    gpu_vram_used = 0
    try:
        import torch
        if torch.cuda.is_available():
            gpu_vram_used = int(torch.cuda.memory_allocated() / (1024 * 1024))
    except Exception:
        pass

    return {
        "status": "ok",
        "phase": 6,
        "phase_name": "local_tts_audio_streaming",
        "gpu_vram_used_mb": gpu_vram_used,
        "stt_ready": stt.is_ready,
        "stt_device": stt.device,
        "llm_ready": llm.is_ready,
        "llm_model": llm.model_id,
        "llm_device": llm.device,
        "tts_ready": tts.is_ready,
        "tts_engine": tts.name,
        "tts_sample_rate": tts.default_sample_rate,
        "recordings_dir": str(RECORDINGS_DIR),
    }

@app.get("/v1/models")
async def get_models():
    """Model status per specifications section 11 & Phase 6 TTS."""
    return {
        "stt": {
            "model": stt.model_size,
            "precision": "int8",
            "device": stt.device,
            "language": "en",
            "ready": stt.is_ready
        },
        "llm": {
            "model": llm.model_id,
            "device": llm.device,
            "ready": llm.is_ready
        },
        "tts": {
            "engine": tts.name,
            "ready": tts.is_ready,
            "sample_rate": tts.default_sample_rate,
            "voices": tts.get_available_voices(),
        }
    }

@app.get("/v1/voices")
async def get_voices():
    """Available TTS voices and audio settings."""
    return {
        "engine": tts.name,
        "default_voice": "af_heart",
        "sample_rate": tts.default_sample_rate,
        "voices": tts.get_available_voices(),
    }

@app.post("/v1/sessions", response_model=CreateSessionResponse)
async def create_session(req: CreateSessionRequest):
    """Session initiation endpoint per specifications section 11."""
    session_id = f"sess_{uuid4().hex[:8]}"
    token = f"tok_{uuid4().hex[:12]}"
    active_sessions[session_id] = {
        "session_id": session_id,
        "client": req.client,
        "thread_id": req.thread_id or f"thread_{uuid4().hex[:6]}",
        "capabilities": req.capabilities,
        "created_at": int(time.time() * 1000),
        "last_active": int(time.time() * 1000),
    }
    logger.info(f"Created session {session_id} for client {req.client}")
    return CreateSessionResponse(
        session_id=session_id,
        ws_url="/ws/v1/session",
        token=token
    )

async def stream_llm_response(
    websocket: WebSocket,
    session_id: str,
    user_text: str,
    user_turn_id: str,
    session_history: list,
    session_config: Optional[dict] = None,
    tts_engine: Optional[BaseTtsEngine] = None,
    stream_id_counter: Optional[list] = None,
    active_generation: Optional[dict] = None,
    is_voice_turn: bool = False,
    on_phase_change: Optional[Callable] = None,
):
    """Streams real-time token-by-token LLM generation and synchronized TTS audio over WebSocket."""
    assistant_turn_id = f"asst_{uuid4().hex[:8]}"
    utterance_id = f"utt_{uuid4().hex[:8]}"
    start_time = time.time()

    cfg = session_config or {}
    mode = cfg.get("mode", "chat_voice_playback")
    call_mode = (mode == "duplex_call")
    tts_enabled = cfg.get("tts_enabled", True)
    engine = tts_engine if tts_engine is not None else tts

    # Enable TTS if explicitly enabled, in duplex call, or responding to a voice input
    should_synthesize_tts = (tts_enabled or call_mode or is_voice_turn) and (engine is not None and engine.is_ready)

    audio_stream_id = None
    if should_synthesize_tts:
        if stream_id_counter is not None:
            audio_stream_id = stream_id_counter[0]
            stream_id_counter[0] += 1
        else:
            audio_stream_id = 2001

    if active_generation is not None:
        active_generation["turn_id"] = assistant_turn_id
        active_generation["utterance_id"] = utterance_id
        active_generation["audio_stream_id"] = audio_stream_id
        active_generation["cancel_reason"] = None
        # (text, start_ms, end_ms) per synthesised clause, so an interruption can
        # truncate history to exactly what the user heard.
        active_generation["segments"] = []
        active_generation["played_ms"] = 0
        active_generation["truncate_to_ms"] = None

    voice_id = cfg.get("voice_id", "af_heart")
    speed = float(cfg.get("speed", 0.96))
    sample_rate = engine.default_sample_rate if engine else 24000

    # Build prompt messages including session conversational history
    messages = llm.build_messages(
        user_text,
        history=session_history,
        memory=(session_config or {}).get("memory"),
        summary=(session_config or {}).get("summary", ""),
    )

    # 1. Send llm_start metadata
    await websocket.send_text(json.dumps({
        "v": 1,
        "type": "llm_start",
        "turn_id": assistant_turn_id,
        "utterance_id": utterance_id,
        "audio_stream_id": audio_stream_id,
        "reply_to": user_turn_id,
        "session_id": session_id,
        "model": llm.model_id,
        "prompt_tokens": len(user_text.split()),
        # Diagnostic: lets a client (or a test) verify that an interrupted turn
        # was recorded truncated rather than in full.
        "history_messages": len(session_history),
        "ts": int(time.time() * 1000)
    }))

    # 2. If TTS is active, send tts.start
    if should_synthesize_tts and audio_stream_id is not None:
        await websocket.send_text(json.dumps({
            "v": 1,
            "type": "tts.start",
            "turn_id": assistant_turn_id,
            "utterance_id": utterance_id,
            "audio_stream_id": audio_stream_id,
            "codec": "pcm_s16le",
            "sample_rate": sample_rate,
            "channels": 1,
            "voice_id": voice_id,
            "ts": int(time.time() * 1000)
        }))

    # 3. Setup queues and cancellation events
    sentence_queue: asyncio.Queue[Optional[str]] = asyncio.Queue(maxsize=6 if not call_mode else 3)
    tts_cancel_event = asyncio.Event()
    llm_cancel_event = asyncio.Event()

    if active_generation is not None:
        active_generation["sentence_queue"] = sentence_queue
        active_generation["tts_cancel_event"] = tts_cancel_event
        active_generation["llm_cancel_event"] = llm_cancel_event

    tts_task: Optional[asyncio.Task] = None

    def supersede_queued_audio() -> None:
        """Drop queued clauses the user is no longer waiting for."""
        dropped = 0
        while True:
            try:
                sentence_queue.get_nowait()
                dropped += 1
            except asyncio.QueueEmpty:
                break
        if dropped:
            logger.info(f"Superseded {dropped} queued TTS clause(s)")

    if should_synthesize_tts and audio_stream_id is not None:
        async def tts_worker():
            seq = 0
            total_samples = 0
            # 100 ms frame size: sample_rate * 2 bytes/sample * 0.1 sec
            frame_bytes = int(sample_rate * 2 * 0.1)
            # Real-time pacing. Without it a three-second clause is pushed in
            # roughly 30 ms, so the client believes it is "speaking" one to two
            # seconds before the speaker makes a sound and a genuine barge-in
            # during that window is not heard at all (§6.5).
            min_frame_interval = frame_bytes / (sample_rate * 2)
            last_frame_at = 0.0

            seg_idx = 0
            phase_notified = False
            try:
                while True:
                    chunk_text = await sentence_queue.get()
                    if chunk_text is None:
                        # Reached end of text stream
                        break

                    if tts_cancel_event.is_set():
                        logger.info(f"TTS synthesis cancelled early for {utterance_id}")
                        break

                    # Synthesize text clause into PCM audio
                    audio_res = await asyncio.to_thread(
                        engine.synthesize,
                        text=chunk_text,
                        voice_id=voice_id,
                        speed=speed,
                    )

                    if tts_cancel_event.is_set():
                        break

                    pcm = audio_res.pcm_bytes
                    if not pcm:
                        continue

                    # Transition to ASSISTANT_SPEAKING on the first audio segment.
                    if not phase_notified and on_phase_change is not None:
                        await on_phase_change(CallPhase.ASSISTANT_SPEAKING, "tts_first_segment")
                        phase_notified = True

                    # Send segment start notification
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "tts.segment",
                        "turn_id": assistant_turn_id,
                        "utterance_id": utterance_id,
                        "audio_stream_id": audio_stream_id,
                        "segment_index": seg_idx,
                        "text": chunk_text,
                        "state": "started",
                        "sample_rate": sample_rate,
                        "duration_ms": int((len(pcm) / (sample_rate * 2)) * 1000),
                        "ts": int(time.time() * 1000)
                    }))

                    total_samples += len(pcm) // 2
                    if active_generation is not None:
                        segments = active_generation.setdefault("segments", [])
                        segments.append([
                            chunk_text,
                            int((total_samples - len(pcm) // 2) / sample_rate * 1000),
                            int(total_samples / sample_rate * 1000),
                        ])

                    # Send 100ms binary frames with 8-byte LE header:
                    # uint32 LE stream_id, uint32 LE sequence
                    for offset in range(0, len(pcm), frame_bytes):
                        if tts_cancel_event.is_set():
                            break
                        slice_payload = pcm[offset : offset + frame_bytes]
                        header = struct.pack("<II", audio_stream_id, seq)
                        seq += 1
                        await websocket.send_bytes(header + slice_payload)
                        if active_generation is not None:
                            active_generation["played_ms"] = int(
                                (seq * frame_bytes) / (sample_rate * 2) * 1000
                            )
                        now = time.perf_counter()
                        due = last_frame_at + min_frame_interval
                        if now < due:
                            await asyncio.sleep(due - now)
                        last_frame_at = time.perf_counter()

                    # Send segment ended notification
                    if not tts_cancel_event.is_set():
                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "tts.segment",
                            "turn_id": assistant_turn_id,
                            "utterance_id": utterance_id,
                            "audio_stream_id": audio_stream_id,
                            "segment_index": seg_idx,
                            "state": "ended",
                            "ts": int(time.time() * 1000)
                        }))
                        seg_idx += 1

                    # Inter-clause gentle pause (80ms silence)
                    if not tts_cancel_event.is_set():
                        silence_bytes = int(sample_rate * 2 * 0.08)
                        header = struct.pack("<II", audio_stream_id, seq)
                        seq += 1
                        await websocket.send_bytes(header + (b"\x00" * silence_bytes))

                if not tts_cancel_event.is_set():
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "tts.end",
                        "turn_id": assistant_turn_id,
                        "utterance_id": utterance_id,
                        "audio_stream_id": audio_stream_id,
                        "cancelled": False,
                        "reason": "complete",
                        "total_frames": seq,
                        "total_samples": total_samples,
                        "duration_ms": int((total_samples / sample_rate) * 1000),
                        "ts": int(time.time() * 1000)
                    }))
            except asyncio.CancelledError:
                logger.info(f"TTS worker cancelled for {utterance_id}")
            except Exception as e:
                logger.error(f"Error in TTS worker {utterance_id}: {e}", exc_info=True)
            # No tts.end here: the cancellation notice is sent by the canceller,
            # outside this task. An `await` inside a cancelled task's own finally
            # can raise again and be swallowed, so the client never learns the
            # stream died.

        tts_task = asyncio.create_task(tts_worker())
        if active_generation is not None:
            active_generation["tts_task"] = tts_task

    # 4. Stream LLM tokens and feed sentence chunker
    chunker = TextChunker(is_call_mode=call_mode)

    full_tokens: list[str] = []
    first_token = True
    ttft_ms = 0

    def commit_history(generated: str) -> str:
        """Append this exchange to the history, truncated to what was heard.

        On an interruption the assistant's message is cut at `played_ms`: the
        next prompt must not contain words the user never heard, or the history
        becomes a record of a conversation that did not happen.
        """
        truncate_to_ms = active_generation.get("truncate_to_ms") if active_generation else None
        text = generated
        if truncate_to_ms is not None:
            segments = (active_generation.get("segments") or []) if active_generation else []
            heard = [seg[0] for seg in segments if seg[2] <= truncate_to_ms]
            text = " ".join(heard).strip()
            logger.info(
                f"Truncated {assistant_turn_id} to played_ms={truncate_to_ms} "
                f"({len(heard)}/{len(segments)} clauses heard)"
            )
        session_history.append({"role": "user", "content": user_text})
        session_history.append({"role": "assistant", "content": text})
        return text

    try:
        async for chunk in llm.generate_stream_async(messages, max_new_tokens=120):
            if llm_cancel_event.is_set():
                logger.info(f"LLM generation stopped early for {assistant_turn_id}")
                break

            if first_token:
                ttft_ms = int((time.time() - start_time) * 1000)
                first_token = False

            full_tokens.append(chunk)
            await websocket.send_text(json.dumps({
                "v": 1,
                "type": "llm_chunk",
                "turn_id": assistant_turn_id,
                "utterance_id": utterance_id,
                "reply_to": user_turn_id,
                "session_id": session_id,
                "delta": chunk,
                "ts": int(time.time() * 1000)
            }))

            if should_synthesize_tts and not tts_cancel_event.is_set():
                new_chunks = chunker.add_token(chunk)
                for nc in new_chunks:
                    if tts_cancel_event.is_set():
                        break
                    # Never block the LLM loop on a full TTS queue: a coroutine
                    # blocked in put() never reaches its cancellation check, so
                    # interruption is delayed by a full clause synthesis. Dropping
                    # a clause the user interrupted is always correct.
                    try:
                        sentence_queue.put_nowait(nc)
                    except asyncio.QueueFull:
                        logger.info("TTS behind; dropping clause and superseding queued audio")
                        supersede_queued_audio()

    except asyncio.CancelledError:
        logger.info(f"LLM streaming task cancelled for {assistant_turn_id}")
        if active_generation is not None and active_generation.get("truncate_to_ms") is not None:
            # An interrupted turn still happened: record it, truncated.
            commit_history("".join(full_tokens).strip())
        return
    except Exception as e:
        logger.error(f"Error during LLM streaming for {assistant_turn_id}: {e}", exc_info=True)

    accumulated = "".join(full_tokens).strip()
    total_duration_ms = int((time.time() - start_time) * 1000)

    if not llm_cancel_event.is_set():
        accumulated = commit_history(accumulated)

        suggestions: list[str] = []
        try:
            suggestions = await llm.generate_suggestions_async(accumulated, user_text=user_text)
        except Exception as e:
            logger.debug(f"Failed to generate suggested replies: {e}")

        await websocket.send_text(json.dumps({
            "v": 1,
            "type": "llm_done",
            "turn_id": assistant_turn_id,
            "utterance_id": utterance_id,
            "reply_to": user_turn_id,
            "session_id": session_id,
            "text": accumulated,
            "tokens": len(full_tokens),
            "suggestions": suggestions,
            "ttft_ms": ttft_ms,
            "duration_ms": total_duration_ms,
            "latency_ms": {
                "ttft": ttft_ms,
                "total": total_duration_ms
            },
            "ts": int(time.time() * 1000)
        }))
        logger.info(
            f"Completed LLM response for {assistant_turn_id} "
            f"({len(full_tokens)} tokens, {total_duration_ms}ms, ttft={ttft_ms}ms, suggestions={suggestions})"
        )

    # 5. Flush any remaining text to TTS worker and wait for completion
    if should_synthesize_tts and not tts_cancel_event.is_set():
        rem = chunker.flush()
        if rem:
            try:
                sentence_queue.put_nowait(rem)
            except asyncio.QueueFull:
                supersede_queued_audio()
                sentence_queue.put_nowait(rem)
        sentence_queue.put_nowait(None)  # EOF
        if tts_task and not tts_task.done():
            try:
                await tts_task
            except Exception as err:
                logger.error(f"Error awaiting TTS task: {err}")
        if on_phase_change is not None and not tts_cancel_event.is_set():
            await on_phase_change(CallPhase.IDLE, "tts_complete")
    elif on_phase_change is not None and not llm_cancel_event.is_set():
        await on_phase_change(CallPhase.IDLE, "llm_complete")

@app.websocket("/ws/v1/session")
async def websocket_session(
    websocket: WebSocket,
    session_id: Optional[str] = Query(None),
    token: Optional[str] = Query(None)
):
    """
    Main WebSocket endpoint supporting:
      - 'hello' / 'session_ready' and 'session.configure' / 'session.ready'
      - 'ping' / 'pong' heartbeat
      - 'text_message' -> echo and real-time streaming LLM + TTS audio
      - 'audio_start' / 'input.start', binary audio streaming, 'audio_end' / 'input.end'
      - 'speech.cancel' (cancels TTS synthesis/audio, keeps LLM text streaming)
      - 'call.barge_in' (cancels both TTS and LLM immediately)
      - 'call.end'
    """
    await websocket.accept()
    current_session_id = session_id or f"sess_{uuid4().hex[:8]}"
    logger.info(f"WebSocket client connected. Session ID: {current_session_id}")

    active_audio_turns: Dict[str, Dict[str, Any]] = {}
    current_audio_turn_id: Optional[str] = None
    session_history: list = []
    vad_config: Dict[str, Any] = dict(DEFAULT_VAD_CONFIG)

    session_config = {
        "mode": "chat_voice_playback",
        "tts_enabled": True,
        "voice_id": "af_heart",
        "speed": 0.96,
        "mic_sample_rate": 16000,
        "playback_sample_rate": tts.default_sample_rate,
        "codec": "pcm_s16le",
    }
    stream_id_counter = [2001]
    active_generation: Dict[str, Any] = {
        "llm_task": None,
        "tts_task": None,
        "sentence_queue": None,
        "tts_cancel_event": None,
        "llm_cancel_event": None,
        "turn_id": None,
        "utterance_id": None,
        "audio_stream_id": None,
        "cancel_reason": None,
        "segments": [],
        "played_ms": 0,
        "truncate_to_ms": None,
    }
    call_phase = CallPhase.IDLE

    async def send(payload: Dict[str, Any]) -> None:
        payload.setdefault("session_id", current_session_id)
        payload.setdefault("ts", int(time.time() * 1000))
        await websocket.send_text(json.dumps(payload))

    async def set_phase(new_phase: CallPhase, reason: str) -> None:
        """Emit call.state on *every* transition, sourced from the §7.4 machine."""
        nonlocal call_phase
        if call_phase == new_phase:
            return
        logger.info(f"call.state {call_phase.value} -> {new_phase.value} ({reason})")
        call_phase = new_phase
        await send({
            "v": 1,
            "type": "call.state",
            "state": new_phase.value,
            "phase": new_phase.value,
            "reason": reason,
        })

    def cancel_active(cancel_tts: bool = True, cancel_llm: bool = True, reason: str = "cancelled"):
        active_generation["cancel_reason"] = reason
        if cancel_tts:
            if active_generation.get("tts_cancel_event"):
                active_generation["tts_cancel_event"].set()
            tts_t = active_generation.get("tts_task")
            if tts_t and not tts_t.done():
                tts_t.cancel()
        if cancel_llm:
            if active_generation.get("llm_cancel_event"):
                active_generation["llm_cancel_event"].set()
            llm_t = active_generation.get("llm_task")
            if llm_t and not llm_t.done():
                llm_t.cancel()

    async def notify_tts_cancelled(reason: str) -> None:
        """Tell the client the audio stream is dead, from outside the dead task."""
        if active_generation.get("audio_stream_id") is None:
            return
        await send({
            "v": 1,
            "type": "tts.end",
            "turn_id": active_generation.get("turn_id"),
            "utterance_id": active_generation.get("utterance_id"),
            "audio_stream_id": active_generation.get("audio_stream_id"),
            "cancelled": True,
            "reason": reason,
        })
        active_generation["tts_task"] = None
        active_generation["audio_stream_id"] = None

    def close_turn(turn_id: str) -> None:
        """Free a turn's buffers. Called on end, cancel and interrupt so a barge-in
        race can never orphan a chunk list for the life of the connection."""
        nonlocal current_audio_turn_id
        active_audio_turns.pop(turn_id, None)
        if current_audio_turn_id == turn_id:
            current_audio_turn_id = next(iter(active_audio_turns), None)

    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                raise WebSocketDisconnect(message.get("code", 1000))

            # 1. Handle Binary Audio Frames (16 kHz PCM16 chunks from client)
            if "bytes" in message and message["bytes"] is not None:
                audio_bytes = message["bytes"]
                if not current_audio_turn_id or current_audio_turn_id not in active_audio_turns:
                    logger.warning(
                        f"Rejected binary frame ({len(audio_bytes)} B): no open turn"
                    )
                    await send({
                        "v": 1,
                        "type": "turn.diagnostic",
                        "reason": "frame_no_turn",
                        "bytes": len(audio_bytes),
                    })
                    continue

                turn = active_audio_turns[current_audio_turn_id]
                payload = audio_bytes
                if turn.get("is_framed", False):
                    if len(audio_bytes) <= 8:
                        await send({
                            "v": 1,
                            "type": "turn.diagnostic",
                            "turn_id": turn["turn_id"],
                            "reason": "frame_too_short",
                            "bytes": len(audio_bytes),
                        })
                        continue
                    # Strip 8-byte LE header: uint32 stream_id, uint32 sequence
                    stream_id, seq = struct.unpack("<II", audio_bytes[:8])
                    payload = audio_bytes[8:]
                    expected = turn.get("expected_seq")
                    if expected is not None and seq != expected:
                        missing = seq - expected if seq > expected else 1
                        turn["frame_gaps"] += max(1, missing)
                        logger.warning(
                            f"Frame gap on {turn['turn_id']}: expected {expected}, got {seq}"
                        )
                        await send({
                            "v": 1,
                            "type": "turn.diagnostic",
                            "turn_id": turn["turn_id"],
                            "reason": "frame_gap",
                            "expected": expected,
                            "received": seq,
                            "missing": max(1, missing),
                        })
                    turn["expected_seq"] = seq + 1
                    turn["stream_id"] = stream_id

                turn["chunks"].append(payload)
                turn["total_bytes"] += len(payload)
                turn["frame_count"] += 1
                if turn["frame_count"] % 25 == 0:
                    logger.info(
                        f"Audio [{turn['turn_id']}]: frame #{turn['frame_count']} "
                        f"({len(payload)} B, total {turn['total_bytes']} B)"
                    )

                # Streaming VAD: the low-latency barge-in signal. This does not
                # wait for a transcript, which is what barge-in used to require.
                vad = turn.get("vad")
                if vad is not None:
                    prob = await asyncio.to_thread(vad.push, payload)
                    if vad.ever_spoke and not turn.get("speech_reported"):
                        turn["speech_reported"] = True
                        await send({
                            "v": 1,
                            "type": "turn.speech_detected",
                            "turn_id": turn["turn_id"],
                            "offset_ms": int(turn["total_bytes"] / (turn["sample_rate"] * 2) * 1000),
                            "speech_start_sample": vad.speech_start_sample,
                            "confidence": round(prob, 3),
                            "source": "server_vad",
                        })
                        await set_phase(CallPhase.USER_SPEAKING, "server_vad")
                continue

            # 2. Handle Text / Control JSON Messages
            if "text" in message and message["text"] is not None:
                raw_message = message["text"]
                try:
                    data = json.loads(raw_message)
                except Exception as e:
                    logger.warning(f"Invalid JSON received: {e}")
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "error",
                        "code": "invalid_json",
                        "message": "Payload must be valid JSON",
                        "retryable": False,
                        "session_id": current_session_id,
                        "ts": int(time.time() * 1000)
                    }))
                    continue

                msg_type = data.get("type")
                ts = data.get("ts", int(time.time() * 1000))

                # Hello / Handshake
                if msg_type == "hello":
                    client_session_id = data.get("session_id") or current_session_id
                    current_session_id = client_session_id
                    thread_id = data.get("thread_id", "thread_default")
                    logger.info(f"Received 'hello' for session {current_session_id}, thread: {thread_id}")

                    ready_payload = {
                        "v": 1,
                        "type": "session_ready",
                        "session_id": current_session_id,
                        "server_time": int(time.time() * 1000),
                        "state": "idle",
                        "tts": {
                            "enabled": session_config["tts_enabled"],
                            "engine": tts.name,
                            "voice_id": session_config["voice_id"],
                            "sample_rate": tts.default_sample_rate,
                        },
                        "ts": int(time.time() * 1000)
                    }
                    await websocket.send_text(json.dumps(ready_payload))

                # Session Configure (Phase 6)
                elif msg_type == "session.configure":
                    mode = data.get("mode", session_config["mode"])
                    session_config["mode"] = mode
                    # The person's own consented memory block. Authoritative on every
                    # configure: absent means none, so withdrawing consent takes
                    # effect on the next configure. Held for this connection only
                    # and never logged or persisted.
                    session_config["memory"] = sanitize_memory(data.get("memory"))
                    # Resuming a conversation: a summary of older turns plus the last
                    # few verbatim. History is seeded only when this connection has
                    # none, so a repeated configure never overwrites a live chat.
                    resume = sanitize_resume(data.get("resume"))
                    if resume:
                        session_config["summary"] = resume["summary"]
                        if not session_history:
                            session_history.extend(resume["recent"])
                    tts_opts = data.get("tts", {})
                    if isinstance(tts_opts, dict):
                        if "enabled" in tts_opts:
                            session_config["tts_enabled"] = bool(tts_opts["enabled"])
                        if "voice_id" in tts_opts:
                            session_config["voice_id"] = str(tts_opts["voice_id"])
                        if "speed" in tts_opts:
                            session_config["speed"] = float(tts_opts["speed"])
                    audio_opts = data.get("audio", {})
                    if isinstance(audio_opts, dict):
                        if "mic_sample_rate" in audio_opts:
                            session_config["mic_sample_rate"] = int(audio_opts["mic_sample_rate"])
                        if "playback_sample_rate" in audio_opts:
                            session_config["playback_sample_rate"] = int(audio_opts["playback_sample_rate"])
                        if "codec" in audio_opts:
                            session_config["codec"] = str(audio_opts["codec"])

                    vad_opts = data.get("vad", {})
                    if isinstance(vad_opts, dict):
                        # Server config wins: a client must not be able to set a
                        # threshold the two halves of the gate disagree on.
                        for key in DEFAULT_VAD_CONFIG:
                            if key in vad_opts:
                                vad_config[key] = vad_opts[key]
                        stt.vad_threshold = float(vad_config["threshold"])
                        stt.vad_neg_threshold = float(vad_config["neg_threshold"])
                        stt.vad_min_speech_ms = int(vad_config["min_speech_ms"])
                        logger.info(f"Session VAD config: {vad_config}")

                    ready_payload = {
                        "v": 1,
                        "type": "session.ready",
                        "session_id": current_session_id,
                        "mode": session_config["mode"],
                        "tts": {
                            "enabled": session_config["tts_enabled"],
                            "engine": tts.name,
                            "voice_id": session_config["voice_id"],
                            "sample_rate": tts.default_sample_rate,
                        },
                        "vad": vad_config,
                        "ts": int(time.time() * 1000)
                    }
                    await websocket.send_text(json.dumps(ready_payload))

                # Moment extraction: quote at most one good moment from a chat
                # message the person just sent. Validated server-side too, and
                # its own task so a slow model never blocks the socket.
                elif msg_type == "moment.extract":
                    request_id = str(data.get("request_id", ""))[:64]
                    message_text = data.get("text")
                    message_text = message_text if isinstance(message_text, str) else ""

                    async def _extract(request_id=request_id, message_text=message_text):
                        moment = await llm.extract_moment_async(message_text)
                        try:
                            await websocket.send_text(json.dumps({
                                "v": 1,
                                "type": "moment.proposal",
                                "request_id": request_id,
                                "text": moment,
                                "ts": int(time.time() * 1000),
                            }))
                        except Exception:
                            logger.debug("moment.proposal not delivered; socket closed")

                    asyncio.create_task(_extract())

                # Rolling summary: fold older turns into a short summary. Runs as
                # its own task so a slow model never blocks the socket, and falls
                # back to an extractive summary rather than failing.
                elif msg_type == "summary.request":
                    request_id = str(data.get("request_id", ""))[:64]
                    previous = clean_summary(data.get("previous_summary"))
                    turns = sanitize_turns(data.get("messages"), max_turns=40)

                    async def _summarize(request_id=request_id, previous=previous, turns=turns):
                        result = await llm.summarize_async(previous, turns)
                        try:
                            await websocket.send_text(json.dumps({
                                "v": 1,
                                "type": "summary.result",
                                "request_id": request_id,
                                "summary": result["summary"],
                                "method": result["method"],
                                "ts": int(time.time() * 1000),
                            }))
                        except Exception:
                            logger.debug("summary.result not delivered; socket closed")

                    asyncio.create_task(_summarize())

                # Speech Cancel (chat mute / stop voice)
                elif msg_type == "speech.cancel":
                    cancel_tts = bool(data.get("cancel_tts", True))
                    cancel_llm = bool(data.get("cancel_llm", False))
                    reason = data.get("reason", "user_cancelled")
                    logger.info(
                        f"Speech cancel received: cancel_tts={cancel_tts}, cancel_llm={cancel_llm}, reason={reason}"
                    )
                    cancel_active(cancel_tts=cancel_tts, cancel_llm=cancel_llm, reason=reason)
                    if cancel_tts:
                        await notify_tts_cancelled(reason)

                # Call Barge-in: stop everything now. The truncation-aware
                # sibling is `turn.interrupted`.
                elif msg_type == "call.barge_in":
                    turn_id = data.get("turn_id")
                    utterance_id = data.get("utterance_id")
                    reason = data.get("reason", "barge_in")
                    logger.info(f"Call barge-in received: turn={turn_id}, utt={utterance_id}, reason={reason}")
                    cancel_active(cancel_tts=True, cancel_llm=True, reason=reason)
                    # Close any in-flight audio turn so new input.start can take over.
                    if current_audio_turn_id and current_audio_turn_id in active_audio_turns:
                        close_turn(current_audio_turn_id)
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "call.state",
                        "state": "listening",
                        "reason": reason,
                        "ts": int(time.time() * 1000)
                    }))
                    await notify_tts_cancelled(reason)

                # Genuine interruption: the client read played_ms BEFORE flushing
                # local playback, so this is exactly what the user heard.
                elif msg_type == "turn.interrupted":
                    turn_id = data.get("turn_id")
                    played_ms = int(data.get("played_ms", 0))
                    interrupted_turn_id = data.get("interrupted_turn_id") or active_generation.get("turn_id")
                    logger.info(
                        f"turn.interrupted [{turn_id}] played_ms={played_ms} "
                        f"assistant={interrupted_turn_id}"
                    )
                    active_generation["truncate_to_ms"] = played_ms
                    cancel_active(cancel_tts=True, cancel_llm=True, reason="user_speech")
                    # Close any in-flight audio turn so new input.start can take over.
                    if current_audio_turn_id and current_audio_turn_id in active_audio_turns:
                        close_turn(current_audio_turn_id)
                    await notify_tts_cancelled("user_speech")
                    await set_phase(CallPhase.USER_SPEAKING, "client_interrupted")

                # The client abandoned the turn (mute, page disposed, call end).
                elif msg_type == "turn.cancel":
                    turn_id = data.get("turn_id") or current_audio_turn_id
                    reason = data.get("reason", "client_cancelled")
                    logger.info(f"turn.cancel [{turn_id}] reason={reason}")
                    if turn_id:
                        close_turn(turn_id)
                        await send({
                            "v": 1,
                            "type": "turn.discarded",
                            "turn_id": turn_id,
                            "reason": "cancelled",
                        })
                    # The prior state is preserved: cancelling a turn while the
                    # assistant speaks must not claim the floor is free.
                    if call_phase in (CallPhase.IDLE, CallPhase.THINKING):
                        await set_phase(CallPhase.IDLE, reason)

                # Call End
                elif msg_type == "call.end":
                    cancel_active(cancel_tts=True, cancel_llm=True, reason="call_ended")
                    for open_turn_id in list(active_audio_turns):
                        close_turn(open_turn_id)
                    session_config["mode"] = "chat_voice_playback"
                    await set_phase(CallPhase.ENDED, "call_ended")

                # Ping / Pong Heartbeat
                elif msg_type == "ping":
                    pong_payload = {
                        "v": 1,
                        "type": "pong",
                        "session_id": current_session_id,
                        "client_ts": ts,
                        "server_time": int(time.time() * 1000),
                        "ts": int(time.time() * 1000)
                    }
                    await websocket.send_text(json.dumps(pong_payload))

                # Text Message -> Echo and Real LLM + TTS Stream Response
                elif msg_type == "text_message":
                    turn_id = data.get("turn_id", f"turn_{uuid4().hex[:6]}")
                    user_text = data.get("text", "")
                    logger.info(f"Received text message [{turn_id}]: {user_text}")

                    # Immediate echo response
                    echo_payload = {
                        "v": 1,
                        "type": "echo",
                        "turn_id": turn_id,
                        "session_id": current_session_id,
                        "text": f"Echo: {user_text}",
                        "ts": int(time.time() * 1000)
                    }
                    await websocket.send_text(json.dumps(echo_payload))

                    if user_text.strip():
                        # Cancel any ongoing generation
                        cancel_active(cancel_tts=True, cancel_llm=True, reason="new_text_message")
                        await notify_tts_cancelled("new_text_message")

                        active_generation["llm_task"] = asyncio.create_task(
                            stream_llm_response(
                                websocket=websocket,
                                session_id=current_session_id,
                                user_text=user_text.strip(),
                                user_turn_id=turn_id,
                                session_history=session_history,
                                session_config=session_config,
                                tts_engine=tts,
                                stream_id_counter=stream_id_counter,
                                active_generation=active_generation,
                                is_voice_turn=False,
                            )
                        )

                # Audio Start / input.start
                #
                # No unconditional cancel here. The old code killed the in-flight
                # response on the mere *assertion* that a turn began: one frame of
                # noise destroyed the answer, and the client then waited out its
                # silence gate to find out nothing had been said. Cancellation now
                # happens on `turn.interrupted`, which the client sends after its
                # own echo-filtered decision.
                elif msg_type in ("audio_start", "input.start"):
                    is_duplex = msg_type == "input.start"
                    turn_id = data.get("turn_id") or data.get("input_id") or f"turn_{uuid4().hex[:6]}"
                    sample_rate = int(data.get("sample_rate", 16000))
                    channels = int(data.get("channels", 1))
                    frame_ms = int(data.get("frame_ms", 20 if is_duplex else 100))
                    encoding = data.get("encoding") or data.get("codec") or "pcm16"
                    is_framed = is_duplex or bool(data.get("framed", False))

                    active_audio_turns[turn_id] = {
                        "turn_id": turn_id,
                        "session_id": current_session_id,
                        "sample_rate": sample_rate,
                        "channels": channels,
                        "frame_ms": frame_ms,
                        "encoding": encoding,
                        "is_framed": is_framed,
                        "chunks": [],
                        "total_bytes": 0,
                        "frame_count": 0,
                        "start_time": time.time(),
                        "expected_seq": None,
                        "stream_id": None,
                        "frame_gaps": 0,
                        "speech_reported": False,
                        "vad": await asyncio.to_thread(stt.new_streaming_vad, sample_rate)
                        if is_duplex else None,
                    }
                    # Always take over: close any stale turn so new audio is
                    # routed to the current turn, not an orphaned one.
                    if current_audio_turn_id is not None and current_audio_turn_id != turn_id:
                        stale = current_audio_turn_id
                        close_turn(stale)
                        logger.info(f"Closed stale turn {stale} for new turn {turn_id}")
                    current_audio_turn_id = turn_id
                    logger.info(
                        f"Turn started: {turn_id} "
                        f"(sr={sample_rate}, ch={channels}, frame_ms={frame_ms}, framed={is_framed}, "
                        f"open_turns={len(active_audio_turns)})"
                    )

                    if is_duplex:
                        await send({
                            "v": 1,
                            "type": "turn.started",
                            "turn_id": turn_id,
                            "sample_rate": sample_rate,
                            "frame_ms": frame_ms,
                            "pre_roll_ms": int(data.get("pre_roll_ms", vad_config["pre_roll_ms"])),
                            "threshold": vad_config["threshold"],
                            "neg_threshold": vad_config["neg_threshold"],
                        })
                        await set_phase(CallPhase.USER_SPEAKING, "input_start")
                    await send({
                        "v": 1,
                        "type": "audio_ack",
                        "turn_id": turn_id,
                        "status": "ready_for_frames",
                    })

                # Audio End / input.end — endpoint the turn, transcribe once, answer.
                elif msg_type in ("audio_end", "input.end"):
                    turn_id = data.get("turn_id") or data.get("input_id") or current_audio_turn_id or "turn_unknown"
                    is_duplex = msg_type == "input.end"
                    logger.info(f"Turn end received for {turn_id}")

                    turn = active_audio_turns.get(turn_id)
                    if not turn or not turn["chunks"]:
                        logger.warning(f"Turn end for {turn_id} with no buffered frames")
                        await send({
                            "v": 1,
                            "type": "audio_received",
                            "turn_id": turn_id,
                            "frames": 0,
                            "bytes": 0,
                            "duration_ms": 0,
                            "wav_file": None,
                        })
                        if turn_id in active_audio_turns:
                            close_turn(turn_id)
                            await send({
                                "v": 1,
                                "type": "turn.discarded",
                                "turn_id": turn_id,
                                "reason": "silence",
                            })
                            await set_phase(CallPhase.IDLE, "no_audio")
                        continue

                    raw_pcm = b"".join(turn["chunks"])
                    total_bytes = len(raw_pcm)
                    frame_count = turn["frame_count"]
                    sr = turn["sample_rate"]
                    ch = turn["channels"]
                    duration_sec = total_bytes / (sr * ch * 2) if (sr * ch * 2) > 0 else 0.0
                    vad = turn.get("vad")
                    probabilities = vad.probabilities if vad is not None else None
                    speech_ms = vad.speech_ms if vad is not None else 0
                    silence_ms = (
                        int(vad.silence_samples / sr * 1000) if vad is not None else 0
                    )
                    close_turn(turn_id)

                    # Optional per-turn dump, off by default and never on the
                    # event loop: the old unconditional write blocked the whole
                    # connection, including the heartbeat, for the write duration.
                    wav_filename = None
                    if DEBUG_RECORDINGS:
                        wav_filename = f"{turn_id}_{int(time.time())}.wav"
                        wav_path = RECORDINGS_DIR / wav_filename

                        def _write_wav(path: Path = wav_path, pcm: bytes = raw_pcm) -> bool:
                            try:
                                with wave.open(str(path), "wb") as wf:
                                    wf.setnchannels(ch)
                                    wf.setsampwidth(2)
                                    wf.setframerate(sr)
                                    wf.writeframes(pcm)
                                return True
                            except Exception as err:
                                logger.error(f"Failed to write WAV {path}: {err}")
                                return False

                        if not await asyncio.to_thread(_write_wav):
                            wav_filename = None

                    await send({
                        "v": 1,
                        "type": "audio_received",
                        "turn_id": turn_id,
                        "frames": frame_count,
                        "bytes": total_bytes,
                        "duration_ms": int(duration_sec * 1000),
                        "wav_file": wav_filename,
                        "frame_gaps": turn["frame_gaps"],
                    })

                    if is_duplex:
                        await send({
                            "v": 1,
                            "type": "turn.endpointed",
                            "turn_id": turn_id,
                            "reason": data.get("reason", "silence"),
                            "speech_end_sample": vad.last_speech_sample if vad else -1,
                            "speech_ms": speech_ms,
                            "silence_ms": silence_ms,
                            "total_ms": int(duration_sec * 1000),
                            "deadline_ms": int(vad_config["min_silence_ms"]),
                            "frame_gaps": turn["frame_gaps"],
                        })
                        await set_phase(CallPhase.THINKING, "endpointed")
                        await send({
                            "v": 1,
                            "type": "turn.processing",
                            "turn_id": turn_id,
                            "stage": "stt",
                            "elapsed_ms": 0,
                        })

                    # One pass: the streaming probability vector is reused, so the
                    # VAD model does not run a second time over the same audio.
                    text, confidence, language, eot_probability, vad_speech_ms = await asyncio.to_thread(
                        stt.analyze, raw_pcm, sr, probabilities
                    )

                    if not text:
                        reason = "silence" if not (probabilities or vad_speech_ms) else "unintelligible"
                        logger.info(f"Discarding turn {turn_id}: {reason}")
                        await send({
                            "v": 1,
                            "type": "transcript_failed",
                            "turn_id": turn_id,
                            "reason": reason,
                            "confidence": round(confidence, 2),
                        })
                        if is_duplex:
                            await send({
                                "v": 1,
                                "type": "turn.discarded",
                                "turn_id": turn_id,
                                "reason": reason,
                                "speech_ms": vad_speech_ms,
                                "confidence": round(confidence, 2),
                            })
                            await set_phase(CallPhase.IDLE, reason)
                        continue

                    logger.info(
                        f"Transcribed turn {turn_id}: \"{text}\" (conf={confidence:.2f}, lang={language})"
                    )
                    await send({
                        "v": 1,
                        "type": "transcript_final",
                        "turn_id": turn_id,
                        "text": text,
                        "stable": True,
                        "language": language,
                        "confidence": round(confidence, 2),
                        "audio_ms": int(duration_sec * 1000),
                    })

                    # The LLM task is registered before anything is awaited, so a
                    # barge-in arriving during transcription cancels this turn
                    # instead of the previous response.
                    cancel_active(cancel_tts=True, cancel_llm=True, reason="new_audio_turn")
                    await notify_tts_cancelled("superseded_by_new_turn")
                    task = asyncio.create_task(
                        stream_llm_response(
                            websocket=websocket,
                            session_id=current_session_id,
                            user_text=text,
                            user_turn_id=turn_id,
                            session_history=session_history,
                            session_config=session_config,
                            tts_engine=tts,
                            stream_id_counter=stream_id_counter,
                            active_generation=active_generation,
                            is_voice_turn=True,
                            on_phase_change=set_phase if is_duplex else None,
                        )
                    )
                    active_generation["llm_task"] = task
                    if is_duplex:
                        await set_phase(CallPhase.THINKING, "transcript_final")

                # Audio Cancel
                elif msg_type == "audio_cancel":
                    turn_id = data.get("turn_id") or current_audio_turn_id or "turn_unknown"
                    reason = data.get("reason", "user_cancelled")
                    logger.info(f"Audio cancel received for turn {turn_id}, reason: {reason}")
                    cancel_active(cancel_tts=True, cancel_llm=True, reason=reason)
                    await notify_tts_cancelled(reason)

                    if turn_id in active_audio_turns:
                        close_turn(turn_id)
                    await send({
                        "v": 1,
                        "type": "turn_cancelled",
                        "turn_id": turn_id,
                        "reason": reason,
                    })

                else:
                    logger.warning(f"Unknown message type: {msg_type}")
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "error",
                        "code": "unknown_type",
                        "message": f"Unsupported message type: {msg_type}",
                        "retryable": False,
                        "session_id": current_session_id,
                        "ts": int(time.time() * 1000)
                    }))

    except WebSocketDisconnect:
        logger.info(f"WebSocket client disconnected cleanly: session {current_session_id}")
    except Exception as e:
        logger.error(f"WebSocket connection error: {e}", exc_info=True)
    finally:
        cancel_active(cancel_tts=True, cancel_llm=True, reason="disconnect")

if __name__ == "__main__":
    import uvicorn
    logger.info("Starting Solace Companion Server on http://0.0.0.0:8000")
    # No reload: it re-executes this module and duplicates the STT, LLM and TTS
    # model loads in the same process.
    uvicorn.run("main:app", host="0.0.0.0", port=8000)
