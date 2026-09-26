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

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("solace_companion")

RECORDINGS_DIR = Path(__file__).resolve().parent / "debug_recordings"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(
    title="Solace Companion Backend",
    version="0.1.0",
    description="Local mental health companion server supporting STT, LLM, and real-time WebSocket communication."
)

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
        "phase": 2,
        "phase_name": "pcm_audio_capture",
        "gpu_vram_used_mb": gpu_vram_used,
        "stt_ready": False,
        "llm_ready": False,
        "recordings_dir": str(RECORDINGS_DIR),
    }

@app.get("/v1/models")
async def get_models():
    """Model status per specifications section 11."""
    return {
        "stt": {
            "model": "faster-distil-whisper-large-v3",
            "precision": "int8",
            "language": "en",
            "ready": False
        },
        "llm": {
            "model": "qwen3-4b-instruct-q4_k_m",
            "context": 4096,
            "quantization": "Q4_K_M",
            "ready": False
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

                # Text Message -> Echo and Mock Stream Response
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

                    if data.get("simulate_stream", True):
                        req_id = f"req_{uuid4().hex[:6]}"
                        start_time = time.time()

                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "llm_start",
                            "turn_id": turn_id,
                            "request_id": req_id,
                            "session_id": current_session_id,
                            "model": "phase1-echo-simulator",
                            "prompt_tokens": len(user_text.split()),
                            "ts": int(time.time() * 1000)
                        }))

                        companion_reply = (
                            f"I hear you. You mentioned: \"{user_text}\". "
                            "Take a gentle breath. We can take this one step at a time."
                        )
                        words = companion_reply.split(" ")
                        ttft_ms = int((time.time() - start_time) * 1000)

                        for idx, word in enumerate(words):
                            delta = word if idx == 0 else " " + word
                            await asyncio.sleep(0.035)
                            await websocket.send_text(json.dumps({
                                "v": 1,
                                "type": "llm_chunk",
                                "turn_id": turn_id,
                                "request_id": req_id,
                                "session_id": current_session_id,
                                "index": idx,
                                "delta": delta,
                                "finish_reason": None,
                                "ts": int(time.time() * 1000)
                            }))

                        total_ms = int((time.time() - start_time) * 1000)
                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "llm_done",
                            "turn_id": turn_id,
                            "request_id": req_id,
                            "session_id": current_session_id,
                            "finish_reason": "stop",
                            "text": companion_reply,
                            "usage": {
                                "prompt_tokens": len(user_text.split()),
                                "completion_tokens": len(words)
                            },
                            "latency_ms": {
                                "ttft": ttft_ms,
                                "total": total_ms
                            },
                            "ts": int(time.time() * 1000)
                        }))

                # Audio Start (Phase 2)
                elif msg_type == "audio_start":
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

                        # Emit transcript_final for UI voice-note confirmation
                        await websocket.send_text(json.dumps({
                            "v": 1,
                            "type": "transcript_final",
                            "turn_id": turn_id,
                            "session_id": current_session_id,
                            "text": f"Voice message ({duration_sec:.1f}s)",
                            "stable": True,
                            "language": "en",
                            "confidence": 1.0,
                            "audio_ms": int(duration_sec * 1000),
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

                # Audio Cancel (Phase 2 - Discard and confirm)
                elif msg_type == "audio_cancel":
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

if __name__ == "__main__":
    import uvicorn
    logger.info("Starting Solace Companion Server on http://0.0.0.0:8000")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
