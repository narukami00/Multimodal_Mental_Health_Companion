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

import numpy as np  # noqa: E402
from fastapi import FastAPI, HTTPException, Request  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from cue import EmotionState, build_cue  # noqa: E402
from pipeline_utils import (  # noqa: E402
    UserBaselineTracker,
    allocate_words_by_weights,
    compute_speech_activity_ratios,
    pool_face_with_quality,
    pool_window_estimates,
)

EMOTION_MOCK = os.environ.get("EMOTION_MOCK", "0") == "1"

if EMOTION_MOCK:
    cv2 = None  # type: ignore[assignment]
    MIN_USABLE = 3
    pool_face = lambda *a, **kw: None  # noqa: E731
else:
    import cv2  # noqa: E402
    from emotion_engine import Engine, MIN_USABLE, pool_face  # noqa: E402


def _build_mock_engine():
    class _MockAudio:
        def features(self, pcm):
            return np.zeros(8, dtype=np.float32)

    class _MockText:
        def features(self, text):
            return np.zeros(8, dtype=np.float32)

    class _MockNorm:
        mu = {"A": np.zeros(8, dtype=np.float32), "T": np.zeros(8, dtype=np.float32), "V": np.zeros(8, dtype=np.float32)}

        def set_user_mean(self, mod, val):
            return None

        def __call__(self, mod, vec):
            return np.asarray(vec, dtype=np.float32)

    class _MockHeads:
        def predict(self, xa, xt, xv):
            mods = [m for m, v in (("A", xa), ("T", xt), ("V", xv)) if v is not None]
            return {
                "valence": 0.0,
                "arousal": 0.0,
                "lv": {"negative": 0.15, "neutral": 0.70, "positive": 0.15},
                "la": {"low": 0.25, "mid": 0.50, "high": 0.25},
                "l7": {"neutral": 0.64, "happy": 0.10, "sad": 0.08, "angry": 0.04, "fear": 0.05, "disgust": 0.04, "surprise": 0.05},
                "modalities": mods,
            }

    class _MockEng:
        audio = _MockAudio()
        text = _MockText()
        norm = _MockNorm()
        heads = _MockHeads()
        face = None

    return _MockEng()

ENG = None
POOL = ThreadPoolExecutor(max_workers=1)  # one engine, one worker: GPU jobs run strictly one after another
STATES, LAST_USED, JOBS, BASELINES = {}, {}, {}, {}
FACES, TRACK = {}, {}  # session_id -> deque of (t, record, embedding) / (tracker state): numbers only, never images
PHONE_FACES = {}  # session_id -> the 1,400-number face vector a phone computed ITSELF (it never sent the pictures): numbers only
FACE_DIM = 1400
FACE_COMPARE = os.environ.get("EMOTION_FACE_COMPARE", "0") == "1"  # testing: when a session has both, log how close they are
FACE_ON = False if EMOTION_MOCK else (os.environ.get("EMOTION_FACE", "0") == "1")
MAX_PENDING_FRAMES, FACE_BUFFER = 2, 400
PENDING = {"frames": 0}
MODEL_VERSION = "emotion-v0-mock" if EMOTION_MOCK else ("emotion-v0-audio-text" + ("-face" if FACE_ON else ""))
MIN_AUDIO_S, SESSION_TTL_S, JOB_TTL_S = 0.3, 7200, 60


@asynccontextmanager
async def lifespan(app):
    global ENG
    t0 = time.time()
    if EMOTION_MOCK:
        ENG = _build_mock_engine()
        print(f"emotion engine ready in {time.time() - t0:.2f} s (mock mode)", flush=True)
    else:
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
        BASELINES.pop(k, None)
        FACES.pop(k, None)
        TRACK.pop(k, None)
        PHONE_FACES.pop(k, None)
        LAST_USED.pop(k, None)
    for k in [k for k, (t, _) in JOBS.items() if now - t > JOB_TTL_S]:
        JOBS.pop(k, None)
    LAST_USED[session_id] = now
    return STATES.setdefault(session_id, EmotionState())


def baseline_of(session_id) -> UserBaselineTracker:
    return BASELINES.setdefault(session_id, UserBaselineTracker(k=8.0))


def clean(o):
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)):
        return None if not np.isfinite(o) else float(o)
    return o


def audio_job(pcm: bytes, sr: int, chunk_s: float = 0.0):
    """Raw audio features: ONE vector, or (chunk_s > 0 and a long recording) one per ~chunk_s window,
    along with per-window speech-activity ratios so silent stretches don't wash out peaks."""
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
    speech_ratios = compute_speech_activity_ratios(parts, sr=16000)
    raws = [ENG.audio.features(p) for p in parts]
    return {"raws": raws, "speech_ratios": speech_ratios}, int(1000 * (time.time() - t))


def face_vector(session_id, window, baseline: Optional[UserBaselineTracker] = None):
    """Normalised face vector and structured quality report. Two sources: phone-computed
    1,400-d vector (wins), or quality-weighted pooled camera frames inside [window]."""
    phone = PHONE_FACES.get(session_id)
    if phone is not None:
        if FACE_COMPARE and FACE_ON and window and len(window) == 2 and FACES.get(session_id):
            _log_face_comparison(session_id, phone, window)
        if baseline is not None:
            ENG.norm.set_user_mean("V", baseline.effective_mean("V", ENG.norm.mu["V"]))
        xv = ENG.norm("V", phone)
        if baseline is not None:
            baseline.update("V", phone)
            ENG.norm.set_user_mean("V", None)
        return xv, {"total_frames": 1, "usable_frames": 1, "reason": None, "source": "phone"}
    if not (FACE_ON and window and len(window) == 2):
        return None, None
    buf = FACES.get(session_id)
    if not buf:
        return None, {"total_frames": 0, "usable_frames": 0, "reason": "no_frames"}
    raw, quality = pool_face_with_quality(
        [(r, e) for t, r, e in list(buf) if window[0] <= t <= window[1]],
        min_usable=MIN_USABLE,
    )
    if raw is None:
        return None, quality
    if baseline is not None:
        ENG.norm.set_user_mean("V", baseline.effective_mean("V", ENG.norm.mu["V"]))
    xv = ENG.norm("V", raw)
    if baseline is not None:
        baseline.update("V", raw)
        ENG.norm.set_user_mean("V", None)
    return xv, quality


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


def estimate_job(audio_data, text, state, xv=None, baseline: Optional[UserBaselineTracker] = None):
    """[audio_data] is None, one raw vector, a list of vectors, or {'raws': [...], 'speech_ratios': [...]}.
    Uses empirical-Bayes user baseline shrinkage, speech-weighted transcript slicing/pooling,
    and cross-modal incongruence detection."""
    if isinstance(audio_data, dict):
        raws = audio_data.get("raws") or [None]
        speech_ratios = audio_data.get("speech_ratios") or [1.0] * len(raws)
    elif isinstance(audio_data, list):
        raws = audio_data
        speech_ratios = [1.0] * len(raws)
    else:
        raws = [audio_data]
        speech_ratios = [1.0]

    words = text.split()
    segments = allocate_words_by_weights(words, speech_ratios) if len(raws) > 1 else [text]
    t = time.time()
    ests = []
    raw_a_seen = []
    raw_t_seen = []
    last_xa = None
    last_xt = None

    if baseline is not None:
        ENG.norm.set_user_mean("A", baseline.effective_mean("A", ENG.norm.mu["A"]))
        ENG.norm.set_user_mean("T", baseline.effective_mean("T", ENG.norm.mu["T"]))
    try:
        for i, raw in enumerate(raws):
            seg = segments[i] if i < len(segments) else ""
            raw_t = ENG.text.features(seg) if seg.strip() else None
            xa = ENG.norm("A", raw) if raw is not None else None
            xt = ENG.norm("T", raw_t) if raw_t is not None else None
            if raw is not None:
                raw_a_seen.append(raw)
            if raw_t is not None:
                raw_t_seen.append(raw_t)
            last_xa, last_xt = xa, xt
            est = ENG.heads.predict(xa, xt, xv)
            if est is not None:
                ests.append(est)

        ms_text = int(1000 * (time.time() - t))
        if not ests:
            return None, None, ms_text, []

        est, window_summaries = pool_window_estimates(ests, speech_ratios)
        if est is not None and len(ests) == 1 and last_xa is not None and last_xt is not None:
            est_a = ENG.heads.predict(last_xa, None, None)
            est_t = ENG.heads.predict(None, last_xt, None)
            if est_a is not None and est_t is not None:
                est = {**est, "modalities": {"A": est_a["lv"], "T": est_t["lv"]}}
    finally:
        if baseline is not None:
            ENG.norm.set_user_mean("A", None)
            ENG.norm.set_user_mean("T", None)

    if baseline is not None:
        if raw_a_seen:
            baseline.update("A", np.mean(np.stack(raw_a_seen), axis=0))
        if raw_t_seen:
            baseline.update("T", np.mean(np.stack(raw_t_seen), axis=0))

    return est, build_cue(est, state, text), ms_text, (window_summaries if len(ests) > 1 else [])


def pack(est, decision, windows=None, calibrated_turns=None, face_quality=None, **timings):
    if est is None:
        out = dict(estimate=None, decision=None, cue=None, model_version=MODEL_VERSION, timings_ms=timings)
    else:
        dv = {k: decision[k] for k in ("mood", "tier", "valence", "arousal", "suppressed", "safety", "pattern", "incongruent") if k in decision}
        clean_est = {k: v for k, v in est.items() if k != "modalities"}
        out = dict(estimate=clean_est, decision=dv, cue=decision["cue"], model_version=MODEL_VERSION, timings_ms=timings)
    if windows:
        out["windows"] = windows
    if calibrated_turns:
        out["calibrated_turns"] = calibrated_turns
    if face_quality is not None:
        out["face_quality"] = face_quality
    return clean(out)


@app.get("/healthz")
async def healthz():
    gpu_mb = 0
    try:
        import torch
        if torch.cuda.is_available():
            gpu_mb = int(torch.cuda.memory_allocated() / 1e6)
    except Exception:
        pass
    return dict(
        ready=ENG is not None,
        mock=EMOTION_MOCK,
        model_version=MODEL_VERSION,
        face=FACE_ON,
        sessions=len(STATES),
        pending_audio=len(JOBS),
        gpu_allocated_mb=gpu_mb,
    )


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
    baseline = baseline_of(req.session_id)
    raw_a, ms_audio = None, None
    job = JOBS.pop((req.session_id, req.turn_id), None) if req.use_audio else None
    if job:
        try:
            raw_a, ms_audio = await asyncio.wait_for(asyncio.shield(job[1]), timeout=max(0.05, req.max_audio_wait_ms / 1000.0))
        except Exception:
            raw_a = None  # audio not ready in time (or failed): continue with text only; the late result is simply dropped
    loop = asyncio.get_running_loop()
    xv, face_quality = await loop.run_in_executor(POOL, face_vector, req.session_id, req.face_window, baseline)
    est, decision, ms_text, windows = await loop.run_in_executor(
        POOL, estimate_job, raw_a, req.text, state, xv, baseline
    )
    out = pack(
        est,
        decision,
        windows=windows,
        calibrated_turns=baseline.counts(),
        face_quality=face_quality,
        audio=ms_audio,
        text=ms_text,
    )
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
    baseline = baseline_of(req.session_id)
    loop = asyncio.get_running_loop()
    est, decision, ms_text, _ = await loop.run_in_executor(
        POOL, estimate_job, None, req.text, state, None, baseline
    )
    return pack(est, decision, calibrated_turns=baseline.counts(), text=ms_text)


@app.post("/v1/emotion/reset")
async def reset(req: ResetReq):
    STATES.pop(req.session_id, None)
    BASELINES.pop(req.session_id, None)
    FACES.pop(req.session_id, None)
    TRACK.pop(req.session_id, None)
    PHONE_FACES.pop(req.session_id, None)
    return dict(ok=True)
