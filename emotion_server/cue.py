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
import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional

MOODS = {  # (valence sign, arousal sign) -> (mood phrase, tone hint)
    ("neg", "low"): ("low or tired", "gentle and unhurried"),
    ("neg", "high"): ("tense or upset", "calm and steady, not cheerful"),
    ("pos", "high"): ("upbeat", "warm, matching their energy lightly"),
    ("pos", "low"): ("calm or content", "relaxed and warm"),
}
CLEAR, HINT = 0.65, 0.50  # calibrated max(P(neg), P(pos)) needed for a 'clear' / 'hint' cue
TEXT_ONLY_MIN = 0.55  # text alone is the weakest single source for a hint
SELF_HARM = re.compile(
    r"\b(kill(ing)? myself|end(ing)? my (own )?life|want(ed)? to die|wanna die|suicid\w*|hurt(ing)? myself|harm(ing)? myself|"
    r"take my own life|don'?t want to (live|be here|be alive)|no reason to live|better off (dead|without me))\b", re.I)


def safety_category(text: str) -> Optional[str]:
    """Conservative placeholder detector: 'self_harm_language' or None. Returns a category only, never the matched text."""
    return "self_harm_language" if text and SELF_HARM.search(text) else None


@dataclass
class EmotionState:
    """Per-session smoothing of valence and arousal across turns (exponential moving average)."""
    alpha: float = 0.5
    v: Optional[float] = None
    a: Optional[float] = None
    turns: int = 0
    moods: List[str] = field(default_factory=list)

    def update(self, p_neg: float, p_pos: float, p_low: float, p_high: float):
        v, a = p_pos - p_neg, p_high - p_low
        self.v = v if self.v is None else self.alpha * v + (1 - self.alpha) * self.v
        self.a = a if self.a is None else self.alpha * a + (1 - self.alpha) * self.a
        self.turns += 1
        return self.v, self.a

    def reset(self):
        self.v = self.a = None
        self.turns = 0
        self.moods.clear()


def build_cue(est: Dict, state: EmotionState, text: str = "") -> Dict:
    """Update the session state with this turn's estimate and return the cue decision."""
    lv, la = est["lv"], est["la"]
    if est.get("pattern") == "V":  # face only: never smoothed into the state and never used for a cue (own analytics at most)
        return dict(cue=None, mood=None, tier=None, valence=lv["positive"] - lv["negative"], arousal=la["high"] - la["low"],
                    suppressed="face only: never used for a cue", safety=safety_category(text), pattern="V")
    v, a = state.update(lv["negative"], lv["positive"], la["low"], la["high"])
    out = dict(cue=None, mood=None, tier=None, valence=v, arousal=a, suppressed=None, safety=safety_category(text), pattern=est.get("pattern"))
    if out["safety"]:
        out["suppressed"] = "self_harm_language: no emotion cue for this turn"
        return out
    strength = max(lv["negative"], lv["positive"])
    floor = TEXT_ONLY_MIN if est.get("pattern") == "T" else HINT
    if lv["neutral"] >= strength or strength < floor:
        out["suppressed"] = "neutral or uncertain"
        return out
    # the smoothed valence decides the sign so that one odd turn does not flip the tone; it must agree in sign with this turn
    sign_now = "pos" if lv["positive"] > lv["negative"] else "neg"
    if abs(v) < 0.15 or (v > 0) != (sign_now == "pos"):
        out["suppressed"] = "smoothed valence disagrees with this turn"
        return out
    mood, tone = MOODS[("pos" if v > 0 else "neg", "high" if a >= 0 else "low")]
    tier = "clear" if strength >= CLEAR else "hint"
    out.update(mood=mood, tier=tier)
    state.moods.append(mood)
    caveat = "a very weak guess" if tier == "hint" else "a weak guess"
    out["cue"] = (f"(Private note, never mention it: their voice and words may suggest they feel {mood}. This is {caveat}, not a fact. "
                  f"Use it only to set your tone: be {tone}. Do not tell them how they feel. If unsure, ignore this note.)")
    return out
