"""Deterministic crisis-language gate for the companion server.

Runs on every final user text (typed or transcribed), independently of the optional emotion service: it never reads an emotion
estimate, so an estimate (or a dead service) cannot weaken it.  Returns a level only, never the matched words.
Phrases live in `safety_phrases.json` (single source, meant to be shared with the app's screener).
"""
import json
import os
import re
from pathlib import Path
from typing import Optional

URGENT = "urgent_support"
SUPPORT = "support_suggested"
COOLDOWN_TURNS = 3  # after an urgent turn, the next turns also get no emotion cue

_PATH = Path(os.environ.get("SOLACE_SAFETY_PHRASES", Path(__file__).with_name("safety_phrases.json")))
_DATA = json.loads(_PATH.read_text(encoding="utf-8"))
_URGENT = tuple(_DATA["urgent"])
_SUPPORT = tuple(_DATA["support"])
DEFAULT_COUNTRY: str = _DATA["default_country"]


def crisis_reply(country: Optional[str] = None, spoken: bool = False) -> str:
    """The fixed supportive text for an urgent turn: the country's local resources, or a generic text without numbers when the
    country is unknown. `spoken=True` writes the numbers out as words so the voice reads them digit by digit."""
    entry = _DATA["countries"].get((country or DEFAULT_COUNTRY).upper()) or _DATA["generic"]
    return entry["spoken" if spoken else "reply"]


ENABLED = os.environ.get("SOLACE_SAFETY_GATE", "on").lower() != "off"


def normalize(text: str) -> str:
    text = text.lower().replace("’", "'").replace("‘", "'")
    text = re.sub(r"[^\w\s']", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def assess(text: str) -> Optional[str]:
    """'urgent_support', 'support_suggested' or None."""
    if not ENABLED or not text:
        return None
    t = normalize(text)
    if any(p in t for p in _URGENT):
        return URGENT
    if any(p in t for p in _SUPPORT):
        return SUPPORT
    return None
