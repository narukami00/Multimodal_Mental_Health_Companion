import asyncio
import json
import logging
from pathlib import Path
import struct
import time
from typing import Any, Dict, Optional
from uuid import uuid4
import wave

from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from stt_service import SttService
from llm_service import LlmService
from text_chunker import TextChunker
from tts_engine import BaseTtsEngine, get_tts_engine, TtsAudioResult

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("solace_companion")

RECORDINGS_DIR = Path(__file__).resolve().parent / "debug_recordings"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)

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

    voice_id = cfg.get("voice_id", "af_heart")
    speed = float(cfg.get("speed", 0.96))
    sample_rate = engine.default_sample_rate if engine else 24000

    # Build prompt messages including session conversational history
    messages = llm.build_messages(user_text, history=session_history)

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

    if should_synthesize_tts and audio_stream_id is not None:
        async def tts_worker():
            seq = 0
            total_samples = 0
            # 100 ms frame size: sample_rate * 2 bytes/sample * 0.1 sec
            frame_bytes = int(sample_rate * 2 * 0.1)

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

                    total_samples += len(pcm) // 2

                    # Send 100ms binary frames with 8-byte LE header:
                    # uint32 LE stream_id, uint32 LE sequence
                    for offset in range(0, len(pcm), frame_bytes):
                        if tts_cancel_event.is_set():
                            break
                        slice_payload = pcm[offset : offset + frame_bytes]
                        header = struct.pack("<II", audio_stream_id, seq)
                        seq += 1
                        await websocket.send_bytes(header + slice_payload)
                        await asyncio.sleep(0.001)

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
            finally:
                if tts_cancel_event.is_set():
                    cancel_reason = "user_cancelled"
                    if active_generation and active_generation.get("cancel_reason"):
                        cancel_reason = active_generation["cancel_reason"]
                    try:
                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "tts.end",
                            "turn_id": assistant_turn_id,
                            "utterance_id": utterance_id,
                            "audio_stream_id": audio_stream_id,
                            "cancelled": True,
                            "reason": cancel_reason,
                            "ts": int(time.time() * 1000)
                        }))
                    except Exception:
                        pass

        tts_task = asyncio.create_task(tts_worker())
        if active_generation is not None:
            active_generation["tts_task"] = tts_task

    # 4. Stream LLM tokens and feed sentence chunker
    chunker = TextChunker(is_call_mode=call_mode)

    full_tokens: list[str] = []
    first_token = True
    ttft_ms = 0

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
                    await sentence_queue.put(nc)

    except asyncio.CancelledError:
        logger.info(f"LLM streaming task cancelled for {assistant_turn_id}")
        return
    except Exception as e:
        logger.error(f"Error during LLM streaming for {assistant_turn_id}: {e}", exc_info=True)

    accumulated = "".join(full_tokens).strip()
    total_duration_ms = int((time.time() - start_time) * 1000)

    if not llm_cancel_event.is_set():
        session_history.append({"role": "user", "content": user_text})
        session_history.append({"role": "assistant", "content": accumulated})

        await websocket.send_text(json.dumps({
            "v": 1,
            "type": "llm_done",
            "turn_id": assistant_turn_id,
            "utterance_id": utterance_id,
            "reply_to": user_turn_id,
            "session_id": session_id,
            "text": accumulated,
            "tokens": len(full_tokens),
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
            f"({len(full_tokens)} tokens, {total_duration_ms}ms, ttft={ttft_ms}ms)"
        )

    # 5. Flush any remaining text to TTS worker and wait for completion
    if should_synthesize_tts and not tts_cancel_event.is_set():
        rem = chunker.flush()
        if rem:
            await sentence_queue.put(rem)
        await sentence_queue.put(None)  # EOF
        if tts_task and not tts_task.done():
            try:
                await tts_task
            except Exception as err:
                logger.error(f"Error awaiting TTS task: {err}")

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
    }

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

    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                raise WebSocketDisconnect(message.get("code", 1000))

            # 1. Handle Binary Audio Frames (16 kHz PCM16 chunks from client)
            if "bytes" in message and message["bytes"] is not None:
                audio_bytes = message["bytes"]
                if current_audio_turn_id and current_audio_turn_id in active_audio_turns:
                    turn = active_audio_turns[current_audio_turn_id]
                    payload = audio_bytes
                    if turn.get("is_framed", False) and len(audio_bytes) > 8:
                        # Strip 8-byte LE header: uint32 stream_id, uint32 sequence
                        payload = audio_bytes[8:]
                    turn["chunks"].append(payload)
                    turn["total_bytes"] += len(payload)
                    turn["frame_count"] += 1
                    if turn["frame_count"] % 10 == 0:
                        logger.info(
                            f"Audio [{current_audio_turn_id}]: received frame #{turn['frame_count']} "
                            f"({len(payload)} B, total {turn['total_bytes']} B)"
                        )
                else:
                    logger.warning(
                        f"Received binary frame ({len(audio_bytes)} bytes) without an active audio turn"
                    )
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
                        "ts": int(time.time() * 1000)
                    }
                    await websocket.send_text(json.dumps(ready_payload))

                # Speech Cancel (Phase 6: chat mute / stop voice)
                elif msg_type == "speech.cancel":
                    cancel_tts = bool(data.get("cancel_tts", True))
                    cancel_llm = bool(data.get("cancel_llm", False))
                    reason = data.get("reason", "user_cancelled")
                    logger.info(
                        f"Speech cancel received: cancel_tts={cancel_tts}, cancel_llm={cancel_llm}, reason={reason}"
                    )
                    cancel_active(cancel_tts=cancel_tts, cancel_llm=cancel_llm, reason=reason)

                # Call Barge-in (Phase 6: interrupt Sol voice during call)
                elif msg_type == "call.barge_in":
                    turn_id = data.get("turn_id")
                    utterance_id = data.get("utterance_id")
                    reason = data.get("reason", "barge_in")
                    logger.info(f"Call barge-in received: turn={turn_id}, utt={utterance_id}, reason={reason}")
                    cancel_active(cancel_tts=True, cancel_llm=True, reason=reason)
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "call.state",
                        "state": "listening",
                        "reason": reason,
                        "ts": int(time.time() * 1000)
                    }))

                # Call End
                elif msg_type == "call.end":
                    cancel_active(cancel_tts=True, cancel_llm=True, reason="call_ended")
                    session_config["mode"] = "chat_voice_playback"
                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "call.state",
                        "state": "idle",
                        "ts": int(time.time() * 1000)
                    }))

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

                # Audio Start / input.start (Phase 2 & 6: cancel any running response on barge-in)
                elif msg_type in ("audio_start", "input.start"):
                    cancel_active(cancel_tts=True, cancel_llm=True, reason="user_speaking")

                    turn_id = data.get("turn_id") or data.get("input_id") or f"turn_{uuid4().hex[:6]}"
                    sample_rate = int(data.get("sample_rate", 16000))
                    channels = int(data.get("channels", 1))
                    frame_ms = int(data.get("frame_ms", 100 if msg_type == "audio_start" else 20))
                    encoding = data.get("encoding") or data.get("codec") or "pcm16"
                    is_framed = (msg_type == "input.start") or bool(data.get("framed", False))

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
                    }
                    current_audio_turn_id = turn_id
                    logger.info(
                        f"Audio turn started: {turn_id} "
                        f"(sample_rate={sample_rate}, channels={channels}, frame_ms={frame_ms}, framed={is_framed})"
                    )

                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "audio_ack",
                        "turn_id": turn_id,
                        "session_id": current_session_id,
                        "status": "ready_for_frames",
                        "ts": int(time.time() * 1000)
                    }))

                # Audio End / input.end (Phase 2 & 6 - Save WAV, STT, and respond with TTS)
                elif msg_type in ("audio_end", "input.end"):
                    turn_id = data.get("turn_id") or data.get("input_id") or current_audio_turn_id or "turn_unknown"
                    logger.info(f"Audio end received for turn {turn_id}")

                    turn = active_audio_turns.get(turn_id)
                    if turn and turn["chunks"]:
                        raw_pcm = b"".join(turn["chunks"])
                        total_bytes = len(raw_pcm)
                        frame_count = turn["frame_count"]
                        sr = turn["sample_rate"]
                        ch = turn["channels"]
                        duration_sec = total_bytes / (sr * ch * 2) if (sr * ch * 2) > 0 else 0.0

                        # Save WAV file to debug_recordings directory
                        wav_filename = f"{turn_id}_{int(time.time())}.wav"
                        wav_path = RECORDINGS_DIR / wav_filename
                        try:
                            with wave.open(str(wav_path), "wb") as wf:
                                wf.setnchannels(ch)
                                wf.setsampwidth(2)  # 16-bit PCM = 2 bytes
                                wf.setframerate(sr)
                                wf.writeframes(raw_pcm)
                            logger.info(
                                f"Successfully saved WAV: {wav_path} "
                                f"({total_bytes} bytes, {duration_sec:.2f}s, {frame_count} frames)"
                            )
                        except Exception as err:
                            logger.error(f"Failed to write WAV file {wav_path}: {err}")
                            wav_filename = None

                        # Emit audio_received confirmation
                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "audio_received",
                            "turn_id": turn_id,
                            "session_id": current_session_id,
                            "frames": frame_count,
                            "bytes": total_bytes,
                            "duration_ms": int(duration_sec * 1000),
                            "wav_file": wav_filename,
                            "ts": int(time.time() * 1000)
                        }))

                        # VAD check followed by Whisper transcription
                        has_speech = await asyncio.to_thread(stt.has_speech, raw_pcm, sr)
                        if not has_speech:
                            logger.info(f"VAD: Silence / no speech detected for turn {turn_id}")
                            await websocket.send_text(json.dumps({
                                "v": 1,
                                "type": "transcript_failed",
                                "turn_id": turn_id,
                                "session_id": current_session_id,
                                "reason": "silence",
                                "confidence": 0.0,
                                "ts": int(time.time() * 1000)
                            }))
                        else:
                            text, confidence, language = await asyncio.to_thread(
                                stt.transcribe, raw_pcm, sr
                            )
                            if text:
                                logger.info(
                                    f"Transcribed turn {turn_id}: \"{text}\" (conf={confidence:.2f}, lang={language})"
                                )
                                await websocket.send_text(json.dumps({
                                    "v": 1,
                                    "type": "transcript_final",
                                    "turn_id": turn_id,
                                    "session_id": current_session_id,
                                    "text": text,
                                    "stable": True,
                                    "language": language,
                                    "confidence": round(confidence, 2),
                                    "audio_ms": int(duration_sec * 1000),
                                    "ts": int(time.time() * 1000)
                                }))

                                # Stream LLM companion response with TTS voice playback!
                                cancel_active(cancel_tts=True, cancel_llm=True, reason="new_audio_turn")
                                active_generation["llm_task"] = asyncio.create_task(
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
                                    )
                                )
                            else:
                                logger.warning(f"Speech detected but transcription empty for turn {turn_id}")
                                await websocket.send_text(json.dumps({
                                    "v": 1,
                                    "type": "transcript_failed",
                                    "turn_id": turn_id,
                                    "session_id": current_session_id,
                                    "reason": "unintelligible",
                                    "confidence": round(confidence, 2),
                                    "ts": int(time.time() * 1000)
                                }))

                        active_audio_turns.pop(turn_id, None)
                    else:
                        logger.warning(f"Audio end received for {turn_id} but no audio frames buffered")
                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "audio_received",
                            "turn_id": turn_id,
                            "session_id": current_session_id,
                            "frames": 0,
                            "bytes": 0,
                            "duration_ms": 0,
                            "wav_file": None,
                            "ts": int(time.time() * 1000)
                        }))

                    if current_audio_turn_id == turn_id:
                        current_audio_turn_id = None

                # Audio Cancel
                elif msg_type == "audio_cancel":
                    cancel_active(cancel_tts=True, cancel_llm=True, reason="user_cancelled")

                    turn_id = data.get("turn_id", current_audio_turn_id or "turn_unknown")
                    reason = data.get("reason", "user_cancelled")
                    logger.info(f"Audio cancel received for turn {turn_id}, reason: {reason}")

                    active_audio_turns.pop(turn_id, None)
                    if current_audio_turn_id == turn_id:
                        current_audio_turn_id = None

                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "turn_cancelled",
                        "turn_id": turn_id,
                        "session_id": current_session_id,
                        "reason": reason,
                        "ts": int(time.time() * 1000)
                    }))

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
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
