"""Emotion SERVICE for the companion server (audio + text; camera frames when EMOTION_FACE=1).  HTTP on 127.0.0.1 only.

  POST /v1/emotion/audio?session_id=&turn_id=&sample_rate=16000   body: raw int16 mono PCM of ONE finished speech turn.
        Starts the audio features at once (runs while the caller's speech-to-text is still working) and returns immediately.
  POST /v1/emotion/finalize   {session_id, turn_id, text, use_audio=true}
        Text features of the transcript + the pending audio features -> calibrated estimate (pattern AT or T), smoothed per session,
        and the hedged cue for the chat model (cue.py).  Returns {estimate, decision, cue, timings_ms}.
  POST /v1/emotion/text       {session_id, text}      text-only estimate (chat / journaling).
  POST /v1/emotion/frame?session_id=&t=   body: ONE upright JPEG (EMOTION_FACE=1 only). The face is tracked per session and the
        numbers (never the image) are kept in memory for about 80 s; finalize may pool the frames of a turn's window ([face_window]).
  POST /v1/emotion/reset      {session_id}
  GET  /healthz
Design rules: the engine is single-threaded behind one worker (GPU jobs never interleave); every call is bounded in time by the
CALLER (it must treat a timeout as 'no cue'); audio and text exist only in memory and are never written or logged (only sizes and
timings); the service must never be required for a call to work.
Run (face venv): face/Scripts/python -m uvicorn emotion_api:app --host 127.0.0.1 --port 8766
"""
import os

for _k, _v in (("OMP_WAIT_POLICY", "PASSIVE"), ("OMP_NUM_THREADS", "2"), ("MKL_NUM_THREADS", "2"), ("OPENBLAS_NUM_THREADS", "2")):
    os.environ.setdefault(_k, _v)

import asyncio  # noqa: E402
from collections import deque  # noqa: E402
import time  # noqa: E402
from concurrent.futures import ThreadPoolExecutor  # noqa: E402
from contextlib import asynccontextmanager  # noqa: E402
from math import gcd  # noqa: E402
from typing import List, Optional  # noqa: E402

import cv2  # noqa: E402
import numpy as np  # noqa: E402
from fastapi import FastAPI, HTTPException, Request  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from cue import EmotionState, build_cue  # noqa: E402
from emotion_engine import Engine, pool_face  # noqa: E402

ENG = None
POOL = ThreadPoolExecutor(max_workers=1)  # one engine, one worker: GPU jobs run strictly one after another
STATES, LAST_USED, JOBS = {}, {}, {}
FACES, TRACK = {}, {}  # session_id -> deque of (t, record, embedding) / (tracker state): numbers only, never images
PHONE_FACES = {}  # session_id -> the 1,400-number face vector a phone computed ITSELF (it never sent the pictures): numbers only
FACE_DIM = 1400
FACE_COMPARE = os.environ.get("EMOTION_FACE_COMPARE", "0") == "1"  # testing: when a session has both, log how close they are
FACE_ON = os.environ.get("EMOTION_FACE", "0") == "1"
MAX_PENDING_FRAMES, FACE_BUFFER = 2, 400
PENDING = {"frames": 0}
MODEL_VERSION = "emotion-v0-audio-text" + ("-face" if FACE_ON else "")
MIN_AUDIO_S, SESSION_TTL_S, JOB_TTL_S = 0.3, 7200, 60


@asynccontextmanager
async def lifespan(app):
    global ENG
    t0 = time.time()
    ENG = Engine(load_face=FACE_ON, load_asr=False)  # the caller supplies the transcript; the camera branch only when asked for
    if FACE_ON:  # the first frame pays for the CUDA kernels and the detector: do it now, not during a call
        for _ in range(2):
            ENG.face.process(np.zeros((640, 360, 3), np.uint8), 0.0)
        ENG.face.reset()
    print(f"emotion engine ready in {time.time() - t0:.0f} s", flush=True)
    yield


app = FastAPI(title="Solace emotion service", version="0.1", lifespan=lifespan)


class Finalize(BaseModel):
    session_id: str
    turn_id: str
    text: str = ""
    use_audio: bool = True
    max_audio_wait_ms: int = 500  # how long to wait for the audio features before answering from the text alone
    face_window: Optional[List[float]] = None  # [t0, t1] on the clock of the /frame calls: pool the frames inside it


class TextReq(BaseModel):
    session_id: str
    text: str


class ResetReq(BaseModel):
    session_id: str


def state_of(session_id):
    now = time.time()
    for k in [k for k, t in LAST_USED.items() if now - t > SESSION_TTL_S]:
        STATES.pop(k, None)
        PHONE_FACES.pop(k, None)
        LAST_USED.pop(k, None)
    for k in [k for k, (t, _) in JOBS.items() if now - t > JOB_TTL_S]:
        JOBS.pop(k, None)
    LAST_USED[session_id] = now
    return STATES.setdefault(session_id, EmotionState())


def clean(o):
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)):
        return None if not np.isfinite(o) else float(o)
    return o


def audio_job(pcm: bytes, sr: int, chunk_s: float = 0.0):
    """Raw audio features: ONE vector, or (chunk_s > 0 and a long recording) one per ~chunk_s window, because the models were trained on
    clips of a few seconds and a feature average over a whole minute drifts out of range."""
    x = np.frombuffer(pcm, np.int16).astype(np.float32) / 32768.0
    if sr != 16000:
        from scipy.signal import resample_poly
        g = gcd(sr, 16000)
        x = resample_poly(x, 16000 // g, sr // g).astype(np.float32)
    t = time.time()
    parts = [x]
    if chunk_s > 0 and len(x) > 1.5 * chunk_s * 16000:
        n = int(len(x) // (chunk_s * 16000))
        size = len(x) // n
        parts = [x[i * size:(i + 1) * size] if i < n - 1 else x[i * size:] for i in range(n)]
    raws = [ENG.audio.features(p) for p in parts]
    return raws, int(1000 * (time.time() - t))


def face_vector(session_id, window):
    """Normalised face vector for this session, or None. Two sources: the numbers a PHONE computed itself (they win: the
    person chose to keep the pictures on the phone), else the pooled camera frames inside [window] (camera off, or fewer
    than 3 usable frames: None)."""
    phone = PHONE_FACES.get(session_id)
    if phone is not None:
        if FACE_COMPARE and FACE_ON and window and len(window) == 2 and FACES.get(session_id):
            _log_face_comparison(session_id, phone, window)
        return ENG.norm("V", phone)
    if not (FACE_ON and window and len(window) == 2):
        return None
    buf = FACES.get(session_id)
    if not buf:
        return None
    raw = pool_face([(r, e) for t, r, e in list(buf) if window[0] <= t <= window[1]])
    return None if raw is None else ENG.norm("V", raw)


def _log_face_comparison(session_id, phone, window):
    """Testing aid (EMOTION_FACE_COMPARE=1): the phone's vector against the one this server pooled from the same frames."""
    raw = pool_face([(r, e) for t, r, e in list(FACES.get(session_id) or []) if window[0] <= t <= window[1]])
    if raw is None:
        print(f"[face-compare {session_id}] the server pooled no vector (fewer than 3 usable frames); phone vector kept", flush=True)
        return
    cos = float(np.dot(raw, phone) / (np.linalg.norm(raw) * np.linalg.norm(phone) + 1e-12))
    pa = ENG.heads.predict(None, None, ENG.norm("V", raw))
    pb = ENG.heads.predict(None, None, ENG.norm("V", phone))
    names = list(pa["l7"].keys())
    ta, tb = max(names, key=lambda n: pa["l7"][n]), max(names, key=lambda n: pb["l7"][n])
    l1 = sum(abs(pa["l7"][n] - pb["l7"][n]) for n in names)
    print(f"[face-compare {session_id}] cosine {cos:.5f}  server top={ta} phone top={tb}  L1 prob diff {l1:.3f}  "
          f"max|diff| first 120 {float(np.abs(raw[:120] - phone[:120]).max()):.4f}  usable frames server={sum(1 for t, r, e in list(FACES.get(session_id) or []) if r['usable'])}",
          flush=True)


def estimate_job(raw_a, text, state, xv=None):
    """[raw_a] is None, one raw vector, or a LIST of them (a long recording in windows): then the transcript is shared out by duration,
    every window is estimated on its own and the probabilities are averaged."""
    raws = raw_a if isinstance(raw_a, list) else [raw_a]
    words = text.split()
    n = len(raws)
    t = time.time()
    ests = []
    for i, raw in enumerate(raws):
        seg = text if n == 1 else " ".join(words[i * len(words) // n:(i + 1) * len(words) // n])
        xt = ENG.text.features(seg) if seg.strip() else None
        xa = ENG.norm("A", raw) if raw is not None else None
        xt = ENG.norm("T", xt) if xt is not None else None
        est = ENG.heads.predict(xa, xt, xv)
        if est is not None:
            ests.append(est)
    ms_text = int(1000 * (time.time() - t))
    if not ests:
        return None, None, ms_text
    est = ests[0] if len(ests) == 1 else {"pattern": max((e["pattern"] for e in ests), key=len),
                                          **{h: {k: float(np.mean([e[h][k] for e in ests])) for k in ests[0][h]} for h in ("l7", "lv", "la")}}
    return est, build_cue(est, state, text), ms_text


def pack(est, decision, **timings):
    if est is None:
        return dict(estimate=None, decision=None, cue=None, model_version=MODEL_VERSION, timings_ms=timings)
    dv = {k: decision[k] for k in ("mood", "tier", "valence", "arousal", "suppressed", "safety", "pattern")}
    return clean(dict(estimate=est, decision=dv, cue=decision["cue"], model_version=MODEL_VERSION, timings_ms=timings))


@app.get("/healthz")
async def healthz():
    import torch
    return dict(ready=ENG is not None, model_version=MODEL_VERSION, face=FACE_ON, sessions=len(STATES), pending_audio=len(JOBS),
                gpu_allocated_mb=int(torch.cuda.memory_allocated() / 1e6) if torch.cuda.is_available() else 0)


@app.post("/v1/emotion/audio")
async def audio(request: Request, session_id: str, turn_id: str, sample_rate: int = 16000, chunk_s: float = 0.0):
    pcm = await request.body()
    if sample_rate < 8000 or sample_rate > 48000:
        raise HTTPException(400, "sample_rate out of range")
    if len(pcm) < 2 * sample_rate * MIN_AUDIO_S:
        return dict(accepted=False, reason="too short")
    state_of(session_id)
    JOBS[(session_id, turn_id)] = (time.time(), asyncio.wrap_future(POOL.submit(audio_job, pcm, sample_rate, chunk_s)))
    return dict(accepted=True, bytes=len(pcm))


@app.post("/v1/emotion/finalize")
async def finalize(req: Finalize):
    state = state_of(req.session_id)
    raw_a, ms_audio = None, None
    job = JOBS.pop((req.session_id, req.turn_id), None) if req.use_audio else None
    if job:
        try:
            raw_a, ms_audio = await asyncio.wait_for(asyncio.shield(job[1]), timeout=max(0.05, req.max_audio_wait_ms / 1000.0))
        except Exception:
            raw_a = None  # audio not ready in time (or failed): continue with text only; the late result is simply dropped
    loop = asyncio.get_running_loop()
    xv = face_vector(req.session_id, req.face_window)
    est, decision, ms_text = await loop.run_in_executor(POOL, estimate_job, raw_a, req.text, state, xv)
    out = pack(est, decision, audio=ms_audio, text=ms_text)
    if xv is not None:
        # The face on its own, for the person's optional "how you looked" view. Never used for the cue or the decision:
        # the face is the weakest signal, so it is reported separately and labelled as a rough guess by the app.
        face_est = await loop.run_in_executor(POOL, ENG.heads.predict, None, None, xv)
        if face_est is not None:
            out["face"] = clean(face_est)
    return out


def frame_job(session_id, jpg, t):
    fr = cv2.imdecode(np.frombuffer(jpg, np.uint8), cv2.IMREAD_COLOR)
    if fr is None:
        return dict(accepted=False, reason="not an image")
    f = ENG.face
    f.prev, f.miss = TRACK.get(session_id, (None, 99))  # the models are shared, the tracker state belongs to the session
    rec, emb = f.process(fr, t)
    TRACK[session_id] = (f.prev, f.miss)
    FACES.setdefault(session_id, deque(maxlen=FACE_BUFFER)).append((t, rec, emb))
    return dict(accepted=True, found=int(rec["found"]), usable=int(rec["usable"]),
                face_h=None if rec["box"] is None else round(rec["box"][3], 3))


@app.post("/v1/emotion/frame")
async def frame(request: Request, session_id: str, t: float):
    if not FACE_ON or ENG is None or ENG.face is None:
        return dict(accepted=False, reason="camera analysis is off")
    jpg = await request.body()
    if not 100 <= len(jpg) <= 2_000_000:
        return dict(accepted=False, reason="bad size")
    if PENDING["frames"] >= MAX_PENDING_FRAMES:
        return dict(accepted=False, reason="busy")  # frames are droppable; audio and text jobs are not
    state_of(session_id)
    PENDING["frames"] += 1
    try:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(POOL, frame_job, session_id, jpg, t)
    finally:
        PENDING["frames"] -= 1


@app.post("/v1/emotion/face_vector")
async def face_vector_in(request: Request, session_id: str):
    """A phone that read the face ITSELF sends only the resulting 1,400 numbers (float32, little endian), never pictures."""
    body = await request.body()
    if len(body) != FACE_DIM * 4:
        raise HTTPException(400, f"expected {FACE_DIM} float32 values")
    vec = np.frombuffer(body, dtype="<f4").astype(np.float32)
    if not np.all(np.isfinite(vec)):
        raise HTTPException(400, "values must be finite")
    state_of(session_id)
    PHONE_FACES[session_id] = vec
    return dict(accepted=True)


@app.post("/v1/emotion/text")
async def text_only(req: TextReq):
    state = state_of(req.session_id)
    loop = asyncio.get_running_loop()
    est, decision, ms_text = await loop.run_in_executor(POOL, estimate_job, None, req.text, state)
    return pack(est, decision, text=ms_text)


@app.post("/v1/emotion/reset")
async def reset(req: ResetReq):
    STATES.pop(req.session_id, None)
    FACES.pop(req.session_id, None)
    TRACK.pop(req.session_id, None)
    PHONE_FACES.pop(req.session_id, None)
    return dict(ok=True)
