"""Journal check-ins: transcribe and read the emotion of what a person says or writes to THEMSELVES. No chat model is involved.

  POST /v1/journal/text    JSON {session_id, text}                          -> {transcript, safety, emotion}
  POST /v1/journal/audio   ?session_id=&sample_rate=16000&face=0|1  body: raw int16 mono PCM of the whole recording
                                                                      -> {transcript, confidence, language, duration_s, safety, emotion}
  POST /v1/journal/frame   ?session_id=       body: ONE upright JPEG taken while recording a video journal -> {usable}

`emotion` is null when the optional emotion service is off or unavailable (the app then saves the entry without an analysis rather
than inventing one). Otherwise it is {pattern, mood, tier, valence, arousal, estimate: {l7, lv, la}, model_version} for the signals
that were present (A voice, T words, V face). Camera frames are only used when the server switch SOLACE_EMOTION_FACE=1 is on AND the app
says `face=1` (its own separate consent); they are kept in memory by the emotion service for this recording only and discarded after.
`safety` is the crisis-language gate's level for the text (or null); the app decides what to show, the words are never echoed or logged.
"""
import asyncio
import logging
import os
import time
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

import safety_gate

logger = logging.getLogger("solace_companion.journal")

MAX_AUDIO_S = 180
MIN_AUDIO_S = 0.5
MAX_TEXT_CHARS = 20000
WINDOW_S = 12.0  # long recordings are read in windows of about this length (the models were trained on short clips)
FACE_SERVER_ENABLED = os.environ.get("SOLACE_EMOTION_FACE") == "1"


class TextEntry(BaseModel):
    session_id: str
    text: str


def _emotion_view(res: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """What the app needs from the emotion service's answer (the chat cue is dropped: there is no chat here)."""
    if not res or not res.get("decision"):
        return None
    d = res["decision"]
    return {"pattern": d.get("pattern"), "mood": d.get("mood"), "tier": d.get("tier"), "valence": d.get("valence"),
            "arousal": d.get("arousal"), "estimate": res.get("estimate"), "model_version": res.get("model_version")}


def build_router(stt: Any, emotion: Any) -> APIRouter:
    router = APIRouter(prefix="/v1/journal")
    stt_lock = asyncio.Lock()
    first_frame_at: Dict[str, float] = {}

    @router.post("/text")
    async def journal_text(entry: TextEntry) -> Dict[str, Any]:
        text = entry.text.strip()
        if not text or len(text) > MAX_TEXT_CHARS:
            raise HTTPException(400, "text is empty or too long")
        res = await emotion.text(entry.session_id, text) if emotion.usable else None
        if emotion.usable:
            await emotion.reset(entry.session_id)
        return {"transcript": text, "safety": safety_gate.assess(text), "emotion": _emotion_view(res)}

    @router.post("/frame")
    async def journal_frame(request: Request, session_id: str) -> Dict[str, Any]:
        if not (FACE_SERVER_ENABLED and emotion.usable):
            return {"usable": None, "accepted": False}
        jpeg = await request.body()
        if not 100 <= len(jpeg) <= 2_000_000:
            return {"usable": None, "accepted": False}
        now = time.monotonic()
        first_frame_at.setdefault(session_id, now)
        res = await emotion.frame(session_id, now, jpeg)
        return {"usable": None if not res or not res.get("accepted") else res.get("usable"), "accepted": bool(res and res.get("accepted"))}

    @router.post("/audio")
    async def journal_audio(request: Request, session_id: str, sample_rate: int = 16000, face: int = 0) -> Dict[str, Any]:
        if not 8000 <= sample_rate <= 48000:
            raise HTTPException(400, "sample_rate out of range")
        pcm = await request.body()
        seconds = len(pcm) / 2 / sample_rate
        if seconds < MIN_AUDIO_S:
            raise HTTPException(400, "recording too short")
        if seconds > MAX_AUDIO_S:
            raise HTTPException(413, f"recording longer than {MAX_AUDIO_S} s")
        turn_id = f"journal_{session_id}"
        upload = None
        if emotion.usable:
            upload = asyncio.ensure_future(emotion.start_audio(session_id, turn_id, pcm, sample_rate, chunk_s=WINDOW_S))  # runs beside the transcription
        async with stt_lock:
            text, confidence, language = await asyncio.to_thread(stt.transcribe, pcm, sample_rate)
        text = (text or "").strip()
        res = None
        if emotion.usable:
            accepted = bool(await upload) if upload is not None else False
            window = None
            start = first_frame_at.pop(session_id, None)
            if face and FACE_SERVER_ENABLED and start is not None:
                window = [start - 0.5, time.monotonic()]
            res = await emotion.finalize(session_id, turn_id, text, use_audio=accepted, max_audio_wait_ms=15000, face_window=window,
                                         timeout_s=30.0)  # a long recording is read window by window
            await emotion.reset(session_id)
        elif upload is not None:
            upload.cancel()
        return {"transcript": text, "confidence": round(float(confidence), 2), "language": language, "duration_s": round(seconds, 1),
                "safety": safety_gate.assess(text), "emotion": _emotion_view(res)}

    return router
