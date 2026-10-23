import asyncio
import logging
import os
import time
from typing import Any, Dict, Optional
from uuid import uuid4

from fastapi import FastAPI, Query, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from llm_service import LlmService
from session import LIVE_SESSIONS, RECORDINGS_DIR, Session
from stt_service import SttService
from tts_engine import get_tts_engine
from video_socket import serve_video
from journal_api import build_router as build_journal_router
from emotion_client import default_client
from model_files import build_router as build_model_files_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("solace_companion")

# Models. Each can be swapped from the environment without touching code.
stt = SttService(model_size=os.environ.get("SOLACE_WHISPER_MODEL", "base.en"))
llm = LlmService(model_id=os.environ.get("SOLACE_LLM_MODEL", "Qwen/Qwen2.5-0.5B-Instruct"))
tts = get_tts_engine(engine_type=os.environ.get("SOLACE_TTS", "auto"))

app = FastAPI(
    title="Solace Companion Backend",
    version="0.2.0",
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
    """Health check endpoint. `*_device` shows where each model actually runs."""
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
        "llm_model": (llm.model_label or llm.model_id) if llm.backend == "llamacpp" else llm.model_id,
        "llm_device": llm.device,
        "llm_backend": llm.backend,
        "tts_ready": tts.is_ready,
        "tts_engine": tts.name,
        "tts_sample_rate": tts.default_sample_rate,
        "recordings_dir": str(RECORDINGS_DIR),
        # Whether emotion readings can be made right now: "off" / "ready" / "unavailable" (switched on but not answering).
        # The app uses it to explain WHY there is no reading instead of guessing.
        "emotion": await default_client().health(),
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
            "backend": llm.backend,
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


@app.websocket("/ws/v1/session")
async def websocket_session(
    websocket: WebSocket,
    session_id: Optional[str] = Query(None),
    token: Optional[str] = Query(None)
):
    """One client connection: chat, push-to-talk voice and live duplex calls.

    The protocol and the turn-taking live in `session.Session`.
    """
    await Session(websocket, stt=stt, llm=llm, tts=tts, session_id=session_id).run()


app.include_router(build_journal_router(stt, default_client()))  # journal check-ins: transcribe + read the emotion, no chat model
app.include_router(build_model_files_router())  # the on-phone speech model, downloaded once by the app with the person's OK


@app.websocket("/ws/v1/video")
async def websocket_video(websocket: WebSocket, session_id: str = Query(...)):
    """Camera frames for the optional emotion module (own socket; refused without the app's separate camera consent)."""
    await serve_video(websocket, session_id, LIVE_SESSIONS)


if __name__ == "__main__":
    import uvicorn
    logger.info("Starting Solace Companion Server on http://0.0.0.0:8000")
    # No reload: it re-executes this module and duplicates the STT, LLM and TTS
    # model loads in the same process.
    uvicorn.run("main:app", host="0.0.0.0", port=8000)
