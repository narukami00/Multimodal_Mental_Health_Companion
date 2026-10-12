"""Client for the local emotion service (slice 1: audio + text).  OPTIONAL and failure-proof by design.

Enabled only when SOLACE_EMOTION=1 (and the app opts in per session with session.configure emotion.enabled).  Every call is bounded
in time and returns None on ANY problem (service down, slow, error), so a call never waits for it or breaks because of it.  A small
circuit breaker stops asking for a few seconds after repeated failures so that a dead service costs nothing per turn.
Audio is sent to 127.0.0.1 only, as one turn of int16 PCM, kept in memory by the service and never written or logged.
Settings (environment): SOLACE_EMOTION (0/1), SOLACE_EMOTION_URL (default http://127.0.0.1:8766), SOLACE_EMOTION_TIMEOUT_S (default 0.8,
the budget for the answer after the transcript is ready).
"""
import logging
import os
import time
from typing import Any, Dict, List, Optional

logger = logging.getLogger("solace_companion.emotion")

BREAKER_FAILS, BREAKER_PAUSE_S = 2, 10.0


class EmotionClient:
    def __init__(self, base_url: Optional[str] = None, timeout_s: Optional[float] = None, enabled: Optional[bool] = None) -> None:
        self.base_url = (base_url or os.environ.get("SOLACE_EMOTION_URL", "http://127.0.0.1:8766")).rstrip("/")
        self.timeout_s = float(timeout_s if timeout_s is not None else os.environ.get("SOLACE_EMOTION_TIMEOUT_S", "0.8"))
        self.enabled = bool(enabled) if enabled is not None else os.environ.get("SOLACE_EMOTION", "0") == "1"
        self._client: Any = None
        self._fails = 0
        self._down_until = 0.0

    # ---- plumbing ---------------------------------------------------------------------------------------------------
    @property
    def usable(self) -> bool:
        return self.enabled and time.monotonic() >= self._down_until

    def _http(self):
        if self._client is None:
            import httpx
            # verify=False: plain HTTP to 127.0.0.1. Without it httpx loads the system CA bundle for every new client, which cost
            # ~0.3-0.7 s on the first call of a session (measured). Local-only by design: the service listens on 127.0.0.1.
            self._client = httpx.AsyncClient(base_url=self.base_url, timeout=self.timeout_s, verify=False)
        return self._client

    def _ok(self) -> None:
        self._fails = 0

    def _fail(self, what: str, err: Exception) -> None:
        self._fails += 1
        logger.warning(f"emotion service {what} failed ({type(err).__name__}); fails={self._fails}")
        if self._fails >= BREAKER_FAILS:
            self._down_until = time.monotonic() + BREAKER_PAUSE_S
            self._fails = 0

    async def _post(self, path: str, what: str, timeout: Optional[float] = None, droppable: bool = False, **kw) -> Optional[Dict[str, Any]]:
        """[droppable] calls (camera frames) may fail or time out without counting against the circuit breaker: losing a frame is free,
        and a slow frame must never switch off the audio and text estimates."""
        if not self.usable:
            return None
        try:
            r = await self._http().post(path, timeout=timeout or self.timeout_s, **kw)
            r.raise_for_status()
            if not droppable:
                self._ok()
            return r.json()
        except Exception as e:  # timeouts, connection errors, HTTP errors: all mean 'no emotion this turn'
            if not droppable:
                self._fail(what, e)
            return None

    # ---- API --------------------------------------------------------------------------------------------------------
    async def start_audio(self, session_id: str, turn_id: str, pcm: bytes, sample_rate: int) -> bool:
        """Hand over one finished turn of mono int16 PCM so its features are computed while speech-to-text runs."""
        r = await self._post("/v1/emotion/audio", "audio", timeout=1.0, params={"session_id": session_id, "turn_id": turn_id, "sample_rate": sample_rate}, content=pcm)
        return bool(r and r.get("accepted"))

    async def finalize(self, session_id: str, turn_id: str, text: str, use_audio: bool = True, max_audio_wait_ms: int = 500,
                       face_window: Optional[List[float]] = None) -> Optional[Dict[str, Any]]:
        """The service waits at most [max_audio_wait_ms] for the turn's audio features, then answers from the text alone.
        [face_window] = [t0, t1] on the clock of `frame` calls: the camera frames inside it are pooled into the estimate."""
        body: Dict[str, Any] = {"session_id": session_id, "turn_id": turn_id, "text": text, "use_audio": use_audio,
                                "max_audio_wait_ms": max_audio_wait_ms}
        if face_window:
            body["face_window"] = [float(face_window[0]), float(face_window[1])]
        return await self._post("/v1/emotion/finalize", "finalize", json=body)

    async def frame(self, session_id: str, t: float, jpeg: bytes) -> Optional[Dict[str, Any]]:
        """One upright JPEG frame taken at [t] (this process's monotonic clock). Droppable: None on any problem."""
        return await self._post("/v1/emotion/frame", "frame", timeout=0.6, droppable=True, params={"session_id": session_id, "t": t}, content=jpeg)

    async def text(self, session_id: str, text: str) -> Optional[Dict[str, Any]]:
        return await self._post("/v1/emotion/text", "text", json={"session_id": session_id, "text": text})

    async def reset(self, session_id: str) -> None:
        await self._post("/v1/emotion/reset", "reset", timeout=0.5, json={"session_id": session_id})

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


_DEFAULT: Optional[EmotionClient] = None


def default_client() -> EmotionClient:
    """One client (HTTP connection pool and circuit breaker) shared by every session of this server process."""
    global _DEFAULT
    if _DEFAULT is None:
        _DEFAULT = EmotionClient()
    return _DEFAULT
