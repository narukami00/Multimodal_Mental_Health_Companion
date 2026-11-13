"""Turn a calibrated emotion estimate into a short, HEDGED note for the chat model (pure Python, no models, easy to test).

Principles (from the research memos and the product decisions):
  * valence/arousal drive the cue (they are the reliable part); the 7 class names are NEVER given to the chat model as fact;
  * a cue is only produced when the calibrated valence is reasonably clear; neutral and uncertain turns get NO cue;
  * the mood is smoothed across turns (EMA) so one odd turn cannot flip the tone;
  * the note says it is a weak guess, asks for tone only, and tells the model to ignore it when unsure;
  * if the user's text contains self-harm language the emotion cue is SUPPRESSED and a safety category is returned for the app:
    that detector is a conservative keyword/regex PLACEHOLDER, not a clinical classifier; false negatives are expected and the real
    safety path (support resources, trusted contacts, consent) must be designed separately.
Estimate input: {"pattern": "AT", "l7": {...}, "lv": {"negative","neutral","positive"}, "la": {"low","mid","high"}}.
"""
import json
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

MOODS = {  # (valence sign, arousal sign) -> (mood phrase, tone hint)
    ("neg", "low"): ("low or tired", "gentle and unhurried"),
    ("neg", "high"): ("tense or upset", "calm and steady, not cheerful"),
    ("pos", "high"): ("upbeat", "warm, matching their energy lightly"),
    ("pos", "low"): ("calm or content", "relaxed and warm"),
}
CLEAR, HINT = 0.65, 0.45  # calibrated max(P(neg), P(pos)) needed for a 'clear' / 'hint' cue
TEXT_ONLY_MIN = 0.55  # text alone is the weakest single source for a hint
SELF_HARM = re.compile(
    r"\b(kill(ing)? myself|end(ing)? my (own )?life|want(ed)? to die|wanna die|suicid\w*|hurt(ing)? myself|harm(ing)? myself|"
    r"take my own life|don'?t want to (live|be here|be alive)|no reason to live|better off (dead|without me))\b", re.I)

_SAFETY_JSON = Path(__file__).resolve().parent.parent / "companion_server" / "safety_phrases.json"


def _normalize_safety_text(text: str) -> str:
    cleaned = re.sub(r"[^a-z0-9\s']", " ", text.lower())
    return " ".join(cleaned.split())


def _load_shared_urgent_phrases() -> tuple[str, ...]:
    if not _SAFETY_JSON.exists():
        return ()
    try:
        data = json.loads(_SAFETY_JSON.read_text(encoding="utf-8"))
        return tuple(_normalize_safety_text(p) for p in data.get("urgent", []) if isinstance(p, str) and p.strip())
    except Exception:
        return ()


SHARED_URGENT_PHRASES = _load_shared_urgent_phrases()


def safety_category(text: str) -> Optional[str]:
    """Conservative placeholder detector: 'self_harm_language' or None. Returns a category only, never the matched text."""
    if not text:
        return None
    if SELF_HARM.search(text):
        return "self_harm_language"
    if SHARED_URGENT_PHRASES:
        norm = f" {_normalize_safety_text(text)} "
        for phrase in SHARED_URGENT_PHRASES:
            if f" {phrase} " in norm:
                return "self_harm_language"
    return None


@dataclass
class EmotionState:
    """Per-session smoothing of valence and arousal across turns (exponential moving average with turn-gap decay)."""
    alpha: float = 0.5
    half_life_s: float = 300.0
    v: Optional[float] = None
    a: Optional[float] = None
    turns: int = 0
    moods: List[str] = field(default_factory=list)
    last_at: Optional[float] = None

    def update(
        self,
        p_neg: float,
        p_pos: float,
        p_low: float,
        p_high: float,
        now: Optional[float] = None,
    ):
        ts = time.monotonic() if now is None else float(now)
        if self.v is not None and self.a is not None and self.last_at is not None and self.half_life_s > 0:
            dt = max(0.0, ts - self.last_at)
            if dt > 0:
                decay = 0.5 ** (dt / self.half_life_s)
                self.v *= decay
                self.a *= decay
        v, a = p_pos - p_neg, p_high - p_low
        self.v = v if self.v is None else self.alpha * v + (1 - self.alpha) * self.v
        self.a = a if self.a is None else self.alpha * a + (1 - self.alpha) * self.a
        self.turns += 1
        self.last_at = ts
        return self.v, self.a

    def reset(self):
        self.v = self.a = None
        self.turns = 0
        self.moods.clear()
        self.last_at = None


def _detect_incongruence(est: Dict) -> Optional[str]:
    """Return 'words_up_tone_down' / 'words_down_tone_up' when audio and text valence clearly diverge."""
    mods = est.get("modalities")
    if not isinstance(mods, dict):
        return None
    lv_a, lv_t = mods.get("A"), mods.get("T")
    if not isinstance(lv_a, dict) or not isinstance(lv_t, dict):
        return None
    a_strength = max(float(lv_a.get("negative", 0.0)), float(lv_a.get("positive", 0.0)))
    t_strength = max(float(lv_t.get("negative", 0.0)), float(lv_t.get("positive", 0.0)))
    if a_strength < TEXT_ONLY_MIN or t_strength < TEXT_ONLY_MIN:
        return None
    if float(lv_a.get("neutral", 0.0)) >= a_strength or float(lv_t.get("neutral", 0.0)) >= t_strength:
        return None
    va = float(lv_a.get("positive", 0.0)) - float(lv_a.get("negative", 0.0))
    vt = float(lv_t.get("positive", 0.0)) - float(lv_t.get("negative", 0.0))
    if va * vt >= 0:
        return None
    return "words_up_tone_down" if vt > 0 and va < 0 else "words_down_tone_up"


def build_cue(est: Dict, state: EmotionState, text: str = "", now: Optional[float] = None) -> Dict:
    """Update the session state with this turn's estimate and return the cue decision."""
    lv, la = est["lv"], est["la"]
    if est.get("pattern") == "V":  # face only: never smoothed into the state and never used for a cue (own analytics at most)
        return dict(cue=None, mood=None, tier=None, valence=lv["positive"] - lv["negative"], arousal=la["high"] - la["low"],
                    suppressed="face only: never used for a cue", safety=safety_category(text), pattern="V", incongruent=False)
    v, a = state.update(lv["negative"], lv["positive"], la["low"], la["high"], now=now)
    inc = _detect_incongruence(est)
    out = dict(cue=None, mood=None, tier=None, valence=v, arousal=a, suppressed=None,
               safety=safety_category(text), pattern=est.get("pattern"), incongruent=inc is not None)
    if out["safety"]:
        out["suppressed"] = "self_harm_language: no emotion cue for this turn"
        return out
    if inc is not None:
        out["tier"] = "hint"
        out["mood"] = "mixed signals"
        if inc == "words_up_tone_down":
            out["cue"] = ("(Private note, never mention it: their words sound steady, though vocal tone may carry quiet tension. "
                          "This is a very weak guess, not a fact. Respond gently without assuming or confronting. If unsure, ignore this note.)")
        else:
            out["cue"] = ("(Private note, never mention it: their words sound heavy even if their voice sounds calm. "
                          "This is a very weak guess, not a fact. Respond gently without assuming or confronting. If unsure, ignore this note.)")
        return out
    strength = max(lv["negative"], lv["positive"])
    floor = TEXT_ONLY_MIN if est.get("pattern") == "T" else HINT
    if lv["neutral"] >= strength or strength < floor:
        out["suppressed"] = "neutral or uncertain"
        if lv["neutral"] >= strength:
            out["mood"] = "even"
        return out
    # the smoothed valence decides the sign so that one odd turn does not flip the tone; it must agree in sign with this turn
    sign_now = "pos" if lv["positive"] > lv["negative"] else "neg"
    turn_mood, tone = MOODS[(sign_now, "high" if la["high"] >= la["low"] else "low")]
    if abs(v) < 0.15 or (v > 0) != (sign_now == "pos"):
        out["suppressed"] = "smoothed valence disagrees with this turn"
        # Preserve the turn's own mood label for user insights even when EMA withholds an LLM tone shift.
        out["mood"] = turn_mood
        return out
    mood, tone = MOODS[("pos" if v > 0 else "neg", "high" if a >= 0 else "low")]
    tier = "clear" if strength >= CLEAR else "hint"
    out.update(mood=mood, tier=tier)
    state.moods.append(mood)
    caveat = "a very weak guess" if tier == "hint" else "a weak guess"
    out["cue"] = (f"(Private note, never mention it: their voice and words may suggest they feel {mood}. This is {caveat}, not a fact. "
                  f"Use it only to set your tone: be {tone}. Do not tell them how they feel. If unsure, ignore this note.)")
    return out
