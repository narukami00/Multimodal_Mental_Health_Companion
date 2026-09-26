import asyncio
import json
import logging
from pathlib import Path
import time
from typing import Any, Dict, Optional
from uuid import uuid4
import wave

from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from stt_service import SttService
from llm_service import LlmService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("solace_companion")

RECORDINGS_DIR = Path(__file__).resolve().parent / "debug_recordings"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)

# Initialize STT and LLM services
stt = SttService(model_size="base.en")
llm = LlmService(model_id="Qwen/Qwen2.5-0.5B-Instruct")

app = FastAPI(
    title="Solace Companion Backend",
    version="0.1.0",
    description="Local mental health companion server supporting STT, LLM, and real-time WebSocket communication."
)

@app.on_event("startup")
async def on_startup():
    logger.info("Server startup: warming up STT & LLM services in background...")
    asyncio.create_task(asyncio.to_thread(stt.initialize))
    asyncio.create_task(asyncio.to_thread(llm.initialize))

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
    """Health check endpoint per specifications section 11."""
    gpu_vram_used = 0
    try:
        import torch
        if torch.cuda.is_available():
            gpu_vram_used = int(torch.cuda.memory_allocated() / (1024 * 1024))
    except Exception:
        pass

    return {
        "status": "ok",
        "phase": 4,
        "phase_name": "local_llm_streaming",
        "gpu_vram_used_mb": gpu_vram_used,
        "stt_ready": stt.is_ready,
        "stt_device": stt.device,
        "llm_ready": llm.is_ready,
        "llm_model": llm.model_id,
        "llm_device": llm.device,
        "recordings_dir": str(RECORDINGS_DIR),
    }

@app.get("/v1/models")
async def get_models():
    """Model status per specifications section 11."""
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
        }
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
):
    """Streams real-time token-by-token LLM generation over WebSocket."""
    assistant_turn_id = f"asst_{uuid4().hex[:8]}"
    start_time = time.time()

    # Build prompt messages including session conversational history
    messages = llm.build_messages(user_text, history=session_history)

    await websocket.send_text(json.dumps({
        "v": 1,
        "type": "llm_start",
        "turn_id": assistant_turn_id,
        "reply_to": user_turn_id,
        "session_id": session_id,
        "model": llm.model_id,
        "prompt_tokens": len(user_text.split()),
        "ts": int(time.time() * 1000)
    }))

    full_tokens: list[str] = []
    first_token = True
    ttft_ms = 0

    try:
        async for chunk in llm.generate_stream_async(messages, max_new_tokens=120):
            if first_token:
                ttft_ms = int((time.time() - start_time) * 1000)
                first_token = False

            full_tokens.append(chunk)
            await websocket.send_text(json.dumps({
                "v": 1,
                "type": "llm_chunk",
                "turn_id": assistant_turn_id,
                "reply_to": user_turn_id,
                "session_id": session_id,
                "delta": chunk,
                "ts": int(time.time() * 1000)
            }))
    except asyncio.CancelledError:
        logger.info(f"LLM streaming cancelled for turn {assistant_turn_id}")
        return
    except Exception as e:
        logger.error(f"Error during LLM streaming for {assistant_turn_id}: {e}", exc_info=True)

    accumulated = "".join(full_tokens).strip()
    total_duration_ms = int((time.time() - start_time) * 1000)

    # Save to session history for conversational context retention
    session_history.append({"role": "user", "content": user_text})
    session_history.append({"role": "assistant", "content": accumulated})

    await websocket.send_text(json.dumps({
        "v": 1,
        "type": "llm_done",
        "turn_id": assistant_turn_id,
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

@app.websocket("/ws/v1/session")
async def websocket_session(
    websocket: WebSocket,
    session_id: Optional[str] = Query(None),
    token: Optional[str] = Query(None)
):
    """
    Main WebSocket endpoint per specifications section 12 & 13.
    Supports:
      - 'hello' handshake -> 'session_ready'
      - 'ping' heartbeat -> 'pong'
      - 'text_message' -> 'echo' and simulated 'llm_chunk' stream
      - audio lifecycle notifications (prepared for Phase 2)
    """
    await websocket.accept()
    current_session_id = session_id or f"sess_{uuid4().hex[:8]}"
    logger.info(f"WebSocket client connected. Session ID: {current_session_id}")

    active_audio_turns: Dict[str, Dict[str, Any]] = {}
    current_audio_turn_id: Optional[str] = None
    session_history: list = []
    active_llm_task: Optional[asyncio.Task] = None

    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                raise WebSocketDisconnect(message.get("code", 1000))

            # 1. Handle Binary Audio Frames (16 kHz PCM16 chunks, ~100ms / 3200 bytes)
            if "bytes" in message and message["bytes"] is not None:
                audio_bytes = message["bytes"]
                if current_audio_turn_id and current_audio_turn_id in active_audio_turns:
                    turn = active_audio_turns[current_audio_turn_id]
                    turn["chunks"].append(audio_bytes)
                    turn["total_bytes"] += len(audio_bytes)
                    turn["frame_count"] += 1
                    if turn["frame_count"] % 10 == 0:
                        logger.info(
                            f"Audio [{current_audio_turn_id}]: received frame #{turn['frame_count']} "
                            f"({len(audio_bytes)} B, total {turn['total_bytes']} B)"
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
                        "ts": int(time.time() * 1000)
                    }
                    await websocket.send_text(json.dumps(ready_payload))

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

                # Text Message -> Echo and Real LLM Stream Response
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
                        # Cancel any ongoing LLM generation
                        if active_llm_task and not active_llm_task.done():
                            active_llm_task.cancel()

                        active_llm_task = asyncio.create_task(
                            stream_llm_response(
                                websocket=websocket,
                                session_id=current_session_id,
                                user_text=user_text.strip(),
                                user_turn_id=turn_id,
                                session_history=session_history,
                            )
                        )

                # Audio Start (Phase 2 & 4: cancel any running LLM stream on barge-in)
                elif msg_type == "audio_start":
                    if active_llm_task and not active_llm_task.done():
                        active_llm_task.cancel()
                    turn_id = data.get("turn_id", f"turn_{uuid4().hex[:6]}")
                    sample_rate = int(data.get("sample_rate", 16000))
                    channels = int(data.get("channels", 1))
                    frame_ms = int(data.get("frame_ms", 100))
                    encoding = data.get("encoding", "pcm16")

                    active_audio_turns[turn_id] = {
                        "turn_id": turn_id,
                        "session_id": current_session_id,
                        "sample_rate": sample_rate,
                        "channels": channels,
                        "frame_ms": frame_ms,
                        "encoding": encoding,
                        "chunks": [],
                        "total_bytes": 0,
                        "frame_count": 0,
                        "start_time": time.time(),
                    }
                    current_audio_turn_id = turn_id
                    logger.info(
                        f"Audio turn started: {turn_id} "
                        f"(sample_rate={sample_rate}, channels={channels}, frame_ms={frame_ms})"
                    )

                    await websocket.send_text(json.dumps({
                        "v": 1,
                        "type": "audio_ack",
                        "turn_id": turn_id,
                        "session_id": current_session_id,
                        "status": "ready_for_frames",
                        "ts": int(time.time() * 1000)
                    }))

                # Audio End (Phase 2 - Save WAV and acknowledge)
                elif msg_type == "audio_end":
                    turn_id = data.get("turn_id", current_audio_turn_id or "turn_unknown")
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

                        # Emit audio_received confirmation per specifications
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

                        # Phase 3: Silero VAD check followed by Whisper transcription
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

                                # Phase 4: Stream LLM companion response to this transcribed voice note
                                if active_llm_task and not active_llm_task.done():
                                    active_llm_task.cancel()

                                active_llm_task = asyncio.create_task(
                                    stream_llm_response(
                                        websocket=websocket,
                                        session_id=current_session_id,
                                        user_text=text,
                                        user_turn_id=turn_id,
                                        session_history=session_history,
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

                # Audio Cancel (Phase 2 & 4 - Discard, cancel active LLM, and confirm)
                elif msg_type == "audio_cancel":
                    if active_llm_task and not active_llm_task.done():
                        active_llm_task.cancel()

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
        if active_llm_task and not active_llm_task.done():
            active_llm_task.cancel()

if __name__ == "__main__":
    import uvicorn
    logger.info("Starting Solace Companion Server on http://0.0.0.0:8000")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
