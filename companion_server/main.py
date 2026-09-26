import asyncio
import json
import logging
import time
from typing import Any, Dict, Optional
from uuid import uuid4

from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("solace_companion")

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
        "phase": 1,
        "phase_name": "websocket_echo",
        "gpu_vram_used_mb": gpu_vram_used,
        "stt_ready": False,  # Phase 1: echo mode
        "llm_ready": False,  # Phase 1: echo mode
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

    try:
        while True:
            raw_message = await websocket.receive_text()
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

            # 1. Hello / Resume Handshake
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

            # 2. Ping / Pong Heartbeat
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

            # 3. Text Message -> Echo and Mock Stream Response
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

                # Also stream token chunks per section 14.5 - 14.7 if requested or as mock LLM simulation
                # This provides full validation of the streaming pipeline for Phase 1!
                if data.get("simulate_stream", True):
                    req_id = f"req_{uuid4().hex[:6]}"
                    start_time = time.time()

                    # llm_start event
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

                    # Simulated conversational companion response
                    companion_reply = (
                        f"I hear you. You mentioned: \"{user_text}\". "
                        "Take a gentle breath. We can take this one step at a time."
                    )
                    words = companion_reply.split(" ")
                    ttft_ms = int((time.time() - start_time) * 1000)

                    for idx, word in enumerate(words):
                        delta = word if idx == 0 else " " + word
                        await asyncio.sleep(0.035)  # simulate ~28 tokens/sec streaming pace
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
                    # llm_done event
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

            # 4. Audio Control Events (Prepared for Phase 2)
            elif msg_type == "audio_start":
                turn_id = data.get("turn_id", f"turn_{uuid4().hex[:6]}")
                logger.info(f"Audio start received for turn {turn_id}")
                await websocket.send_text(json.dumps({
                    "v": 1,
                    "type": "audio_ack",
                    "turn_id": turn_id,
                    "session_id": current_session_id,
                    "status": "ready_for_frames",
                    "ts": int(time.time() * 1000)
                }))

            elif msg_type == "audio_cancel":
                turn_id = data.get("turn_id", "unknown")
                logger.info(f"Audio cancel received for turn {turn_id}")
                await websocket.send_text(json.dumps({
                    "v": 1,
                    "type": "turn_cancelled",
                    "turn_id": turn_id,
                    "session_id": current_session_id,
                    "ts": int(time.time() * 1000)
                }))

            elif msg_type == "audio_end":
                turn_id = data.get("turn_id", "unknown")
                logger.info(f"Audio end received for turn {turn_id}")
                # Phase 1 stub for audio_end
                await websocket.send_text(json.dumps({
                    "v": 1,
                    "type": "transcript_final",
                    "turn_id": turn_id,
                    "session_id": current_session_id,
                    "text": "[Phase 1 Echo: Audio capture stub active]",
                    "stable": True,
                    "language": "en",
                    "confidence": 1.0,
                    "audio_ms": data.get("duration_ms", 1000),
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
