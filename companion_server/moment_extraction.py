"""Finding one good moment in something the person said, safely.

Pure helpers, no model import. The model may only *quote*: whatever it returns is
checked here against the original message, against a sensitive-topic filter that
mirrors the app's `momentIsSensitive`, and against a length cap. If anything is
off the answer is thrown away, so the worst outcome is "no proposal".
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

MAX_INPUT_CHARS = 1200
MAX_MOMENT_CHARS = 140
MIN_OVERLAP = 0.8

EXTRACT_INSTRUCTION = (
    "From the person's message, copy ONE sentence in which they say something "
    "good happened to them or that they enjoyed. Copy it exactly as written, "
    "without changing any words. If there is no such sentence, reply with the "
    "single word NONE."
)

# Mirrors lib/domain/memory/moment_extractor.dart (momentIsSensitive). Whole
# words only, so "therapist" is not caught by "rape".
_SENSITIVE_WORDS = [
    r"suicid\w*",
    r"kill (?:myself|me)",
    r"end it all",
    r"want to die",
    r"self[- ]?harm\w*",
    r"hurt(?:ing)? myself",
    r"overdos\w*",
    r"died",
    r"dead",
    r"death",
    r"funeral",
    r"passed away",
    r"grie[fv]\w*",
    r"miscarriage",
    r"diagnos\w*",
    r"cancer",
    r"hospital\w*",
    r"medication",
    r"panic attack\w*",
    r"abus\w*",
    r"assault\w*",
    r"rape\w*",
    r"debt",
    r"evict\w*",
    r"bankrupt\w*",
    r"laid off",
    r"fired",
]
_SENSITIVE = [re.compile(r"\b" + w + r"\b") for w in _SENSITIVE_WORDS]


def is_sensitive(text: str) -> bool:
    lower = text.lower()
    return any(p.search(lower) for p in _SENSITIVE)


def _words(text: str) -> List[str]:
    return re.findall(r"[a-z0-9']+", text.lower())


def extraction_messages(text: str) -> List[Dict[str, str]]:
    """The prompt that asks the model to quote one good moment."""
    clipped = " ".join(text.split())[:MAX_INPUT_CHARS]
    return [
        {"role": "system", "content": EXTRACT_INSTRUCTION},
        {"role": "user", "content": clipped},
    ]


def validate_moment(original: str, candidate: Any) -> Optional[str]:
    """The candidate as a single clean line, or None if it is not acceptable.

    Acceptable means: a non-empty single line within the length cap, not the
    model saying NONE, not about a sensitive topic (in the candidate *or* in the
    original message), and made of the person's own words: at least 80% of its
    words appear in the original.
    """
    if not isinstance(candidate, str):
        return None
    line = " ".join(candidate.split()).strip(" \"'“”")
    if not line or line.upper().rstrip(".") == "NONE":
        return None
    if len(line) > MAX_MOMENT_CHARS:
        return None
    if is_sensitive(line) or is_sensitive(original):
        return None
    mine = _words(line)
    if len(mine) < 4:
        return None
    theirs = set(_words(original))
    overlap = sum(1 for w in mine if w in theirs) / len(mine)
    if overlap < MIN_OVERLAP:
        return None
    return line
