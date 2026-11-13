"""Pure numpy/Python signal-quality, calibration, and windowing helpers for `emotion_server`.

Kept separate from model weights so every B1/B2/B3 algorithm can be unit-tested
deterministically without GPU hardware or large checkpoints.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple
import numpy as np


# ---------------------------------------------------------------------------
# B1: Empirical-Bayes per-user baseline shrinkage
# ---------------------------------------------------------------------------

class UserBaselineTracker:
    """Tracks per-modality running user feature means with empirical-Bayes shrinkage.

    Formula: mu_eff = (n / (n + k)) * mean_user + (k / (n + k)) * mu_ref
    where k is the shrinkage prior (default 8 turns) so small n never overfits.
    """

    def __init__(self, k: float = 8.0) -> None:
        self.k = float(k)
        self._sums: Dict[str, np.ndarray] = {}
        self._counts: Dict[str, int] = {}

    def update(self, mod: str, raw_vec: Optional[np.ndarray]) -> None:
        if raw_vec is None:
            return
        arr = np.asarray(raw_vec, dtype=np.float32)
        if arr.ndim != 1 or not np.all(np.isfinite(arr)):
            return
        if mod not in self._sums:
            self._sums[mod] = arr.astype(np.float64).copy()
            self._counts[mod] = 1
        else:
            if self._sums[mod].shape != arr.shape:
                return
            self._sums[mod] += arr.astype(np.float64)
            self._counts[mod] += 1

    def count(self, mod: str) -> int:
        return self._counts.get(mod, 0)

    def counts(self) -> Dict[str, int]:
        return dict(self._counts)

    def effective_mean(self, mod: str, mu_ref: np.ndarray) -> np.ndarray:
        n = self._counts.get(mod, 0)
        if n <= 0 or mod not in self._sums:
            return mu_ref
        user_mean = (self._sums[mod] / n).astype(np.float32)
        w = n / (n + self.k)
        return (w * user_mean + (1.0 - w) * np.asarray(mu_ref, dtype=np.float32)).astype(np.float32)

    def reset(self) -> None:
        self._sums.clear()
        self._counts.clear()


# ---------------------------------------------------------------------------
# B2: Speech-presence (VAD-like) long-recording windowing & pooling
# ---------------------------------------------------------------------------

def compute_speech_activity_ratios(
    parts: Sequence[np.ndarray],
    sr: int = 16000,
    frame_ms: int = 32,
) -> List[float]:
    """Return active-speech fraction in [0.0, 1.0] for each audio window."""
    if not parts:
        return []
    frame_len = max(1, int(sr * frame_ms / 1000))
    all_rms: List[np.ndarray] = []
    for p in parts:
        arr = np.asarray(p, dtype=np.float32)
        n_frames = max(1, len(arr) // frame_len)
        usable = arr[: n_frames * frame_len] if len(arr) >= frame_len else arr
        if len(usable) == 0:
            all_rms.append(np.zeros(1, dtype=np.float32))
            continue
        if len(usable) < frame_len:
            rms = np.array([float(np.sqrt(np.mean(usable * usable)))], dtype=np.float32)
        else:
            frames = usable.reshape(n_frames, frame_len)
            rms = np.sqrt(np.mean(frames * frames, axis=1)).astype(np.float32)
        all_rms.append(rms)

    pooled = np.concatenate(all_rms) if all_rms else np.zeros(1, dtype=np.float32)
    ref_rms = float(np.percentile(pooled, 85)) if len(pooled) else 0.0
    gate = max(0.008, 0.22 * ref_rms)

    ratios: List[float] = []
    for rms in all_rms:
        if len(rms) == 0:
            ratios.append(0.0)
        else:
            ratios.append(float(np.mean(rms >= gate)))
    return ratios


def allocate_words_by_weights(words: Sequence[str], weights: Sequence[float]) -> List[str]:
    """Distribute transcript words across windows proportionally to speech activity."""
    n = len(weights)
    if n == 0:
        return []
    if n == 1 or not words:
        joined = " ".join(words)
        return [joined] + [""] * (n - 1) if n > 1 else [joined]

    clean_w = [max(0.0, float(w)) for w in weights]
    total_w = sum(clean_w)
    if total_w <= 1e-9:
        clean_w = [1.0] * n
        total_w = float(n)

    total_words = len(words)
    segments: List[str] = []
    cursor = 0
    cum_w = 0.0
    for i, w in enumerate(clean_w):
        cum_w += w
        end = total_words if i == n - 1 else int(round(total_words * (cum_w / total_w)))
        end = max(cursor, min(total_words, end))
        segments.append(" ".join(words[cursor:end]))
        cursor = end
    return segments


def pool_window_estimates(
    ests: Sequence[Dict[str, Any]],
    speech_ratios: Sequence[float],
) -> Tuple[Optional[Dict[str, Any]], List[Dict[str, Any]]]:
    """Pool per-window emotion dicts weighted by speech presence & peak confidence."""
    if not ests:
        return None, []

    weights: List[float] = []
    window_summaries: List[Dict[str, Any]] = []
    for idx, est in enumerate(ests):
        sr_ratio = float(speech_ratios[idx]) if idx < len(speech_ratios) else 1.0
        lv = est["lv"]
        la = est["la"]
        peak = max(float(lv["negative"]), float(lv["positive"]))
        # Speech presence gates silent stretches; non-neutral peak prevents bland
        # filler frames from washing out an emotional moment.
        w = max(0.02, sr_ratio) * (0.5 + 0.5 * peak)
        weights.append(w)

        v = float(lv["positive"]) - float(lv["negative"])
        a = float(la["high"]) - float(la["low"])
        if max(lv["negative"], lv["positive"]) <= lv["neutral"]:
            mood = "neutral"
        elif v >= 0:
            mood = "upbeat" if a >= 0 else "calm"
        else:
            mood = "tense" if a >= 0 else "low"
        window_summaries.append({
            "index": idx,
            "speech_ratio": round(sr_ratio, 3),
            "valence": round(v, 3),
            "arousal": round(a, 3),
            "mood": mood,
        })

    if len(ests) == 1:
        return ests[0], window_summaries

    w_arr = np.asarray(weights, dtype=np.float64)
    w_arr = w_arr / np.sum(w_arr)
    pooled: Dict[str, Any] = {
        "pattern": max((e["pattern"] for e in ests), key=len),
    }
    for head in ("l7", "lv", "la"):
        keys = list(ests[0][head].keys())
        pooled[head] = {
            k: float(sum(w_arr[i] * float(ests[i][head][k]) for i in range(len(ests))))
            for k in keys
        }
    return pooled, window_summaries


# ---------------------------------------------------------------------------
# B3: Face quality weighting & structured abstention metadata
# ---------------------------------------------------------------------------

def _weighted_mean_std(arr: np.ndarray, weights: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    w = weights / np.sum(weights)
    mean = np.sum(arr * w[:, None], axis=0)
    var = np.sum(((arr - mean) ** 2) * w[:, None], axis=0)
    return mean, np.sqrt(np.maximum(var, 0.0))


def _frame_quality_weight(rec: Dict[str, Any]) -> float:
    blur = float(rec.get("blur", 100.0))
    bright = float(rec.get("bright", 128.0))
    det_score = float(rec.get("det_score", 0.9))
    yaw = float(rec.get("yaw", 0.0))
    pitch = float(rec.get("pitch", 0.0))

    blur_w = float(np.clip(blur / 80.0, 0.15, 1.0)) if np.isfinite(blur) else 0.7
    if np.isfinite(bright):
        if bright < 35.0:
            bright_w = max(0.15, bright / 35.0)
        elif bright > 230.0:
            bright_w = max(0.2, (255.0 - bright) / 25.0)
        else:
            bright_w = 1.0
    else:
        bright_w = 0.8
    pose_w = 1.0
    if np.isfinite(yaw) and np.isfinite(pitch):
        pose_w = max(0.2, (1.0 - min(abs(yaw) / 45.0, 1.0) * 0.5) * (1.0 - min(abs(pitch) / 35.0, 1.0) * 0.5))
    det_w = float(np.clip(det_score, 0.3, 1.0)) if np.isfinite(det_score) else 0.8
    return blur_w * bright_w * pose_w * det_w


def pool_face_with_quality(
    frames: Sequence[Tuple[Dict[str, Any], Optional[np.ndarray]]],
    min_usable: int = 3,
    extreme_blur_threshold: float = 15.0,
) -> Tuple[Optional[np.ndarray], Dict[str, Any]]:
    """Quality-weighted pooling of usable face frames plus structured abstention metadata."""
    total = len(frames)
    if total == 0:
        return None, {"total_frames": 0, "usable_frames": 0, "reason": "no_frames"}

    usable = [(r, e) for r, e in frames if r.get("usable") == 1 and e is not None]
    if len(usable) >= min_usable:
        crisp = [
            (r, e)
            for r, e in usable
            if not np.isfinite(r.get("blur", np.nan)) or float(r["blur"]) >= extreme_blur_threshold
        ]
        if len(crisp) >= min_usable:
            usable = crisp

    if len(usable) < min_usable:
        found = sum(1 for r, _ in frames if r.get("found") == 1)
        if found == 0:
            reason = "no_face_detected"
        else:
            blurs = [float(r["blur"]) for r, _ in frames if np.isfinite(r.get("blur", np.nan))]
            brights = [float(r["bright"]) for r, _ in frames if np.isfinite(r.get("bright", np.nan))]
            angles = [
                (abs(float(r["yaw"])), abs(float(r["pitch"])))
                for r, _ in frames
                if np.isfinite(r.get("yaw", np.nan)) and np.isfinite(r.get("pitch", np.nan))
            ]
            if brights and float(np.mean(brights)) < 35.0:
                reason = "low_light"
            elif blurs and float(np.mean(blurs)) < extreme_blur_threshold:
                reason = "high_blur"
            elif angles and any(y > 45.0 or p > 35.0 for y, p in angles):
                reason = "off_angle"
            else:
                reason = "too_few_usable"
        return None, {"total_frames": total, "usable_frames": len(usable), "reason": reason}

    weights = np.asarray([_frame_quality_weight(r) for r, _ in usable], dtype=np.float32)
    L = np.stack([r["logits"] for r, _ in usable]).astype(np.float32)
    B = np.stack([r["bs"] for r, _ in usable]).astype(np.float32)
    E = np.stack([e for _, e in usable]).astype(np.float16).astype(np.float32)

    l_mean, l_std = _weighted_mean_std(L, weights)
    b_mean, b_std = _weighted_mean_std(B, weights)
    e_mean, _ = _weighted_mean_std(E, weights)
    vec = np.concatenate([l_mean, l_std, b_mean, b_std, e_mean]).astype(np.float32)
    return vec, {"total_frames": total, "usable_frames": len(usable), "reason": None}
