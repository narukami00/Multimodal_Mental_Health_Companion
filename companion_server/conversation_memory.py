"""Pure helpers for conversation resume and rolling summaries.

No model and no torch import here, so everything is fast to test. The client
owns the transcript; the server only receives what it needs for one connection
and never persists it (CHAT_FEATURES s17-19).
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

MAX_RESUME_TURNS = 12
MAX_TURN_CHARS = 600
MAX_SUMMARY_CHARS = 1200
MAX_SUMMARY_INPUT_TURNS = 40

SUMMARY_INSTRUCTION = (
    "Summarize this conversation for a compassionate companion. "
    "Preserve emotional tone, important facts, unresolved concerns, and what the "
    "person responded well to. Write in the third person about 'the user'. "
    "Do not diagnose and do not add clinical labels unless the user used them. "
    "Keep it under 120 words, as plain sentences with no lists."
)

_ROLES = ("user", "assistant")


def _clean(value: Any, limit: int) -> str:
    """One line of plain text: no control characters, collapsed spaces, capped."""
    if not isinstance(value, str):
        return ""
    cleaned = "".join(ch if ch >= " " else " " for ch in value)
    cleaned = " ".join(cleaned.split())
    return cleaned[:limit].strip()


def sanitize_turns(raw: Any, max_turns: int = MAX_RESUME_TURNS) -> List[Dict[str, str]]:
    """Validate a list of {role, content} turns, keeping the most recent ones."""
    if not isinstance(raw, list):
        return []
    turns: List[Dict[str, str]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        content = _clean(item.get("content"), MAX_TURN_CHARS)
        if role in _ROLES and content:
            turns.append({"role": role, "content": content})
    return turns[-max_turns:]


def sanitize_resume(raw: Any) -> Optional[Dict[str, Any]]:
    """Validate the optional `resume` block from `session.configure`.

    Returns None when there is nothing usable. The summary and every turn are
    flattened to plain capped text, so nothing but short sentences can reach the
    prompt.
    """
    if not isinstance(raw, dict):
        return None
    summary = _clean(raw.get("summary"), MAX_SUMMARY_CHARS)
    recent = sanitize_turns(raw.get("recent"))
    if not summary and not recent:
        return None
    return {"summary": summary, "recent": recent}


def summary_messages(
    previous_summary: str, turns: List[Dict[str, str]]
) -> List[Dict[str, str]]:
    """The prompt that asks the model to fold older turns into the summary."""
    lines = []
    if previous_summary:
        lines.append("Earlier summary: " + previous_summary)
        lines.append("")
    lines.append("New conversation to fold in:")
    for turn in turns[-MAX_SUMMARY_INPUT_TURNS:]:
        speaker = "User" if turn["role"] == "user" else "Sol"
        lines.append(f"{speaker}: {turn['content']}")
    return [
        {"role": "system", "content": SUMMARY_INSTRUCTION},
        {"role": "user", "content": chr(10).join(lines)},
    ]


def clean_summary(text: Any) -> str:
    """A model's summary, made safe to store and to put back into a prompt."""
    return _clean(text, MAX_SUMMARY_CHARS)


def extractive_summary(previous_summary: str, turns: List[Dict[str, str]]) -> str:
    """A fallback that needs no model: what the person said, shortened.

    Keeps the earlier summary, then the first words of the person's own
    messages. It adds nothing of its own, so it cannot invent or diagnose.
    """
    said: List[str] = []
    for turn in turns:
        if turn["role"] != "user":
            continue
        content = turn["content"]
        said.append(content if len(content) <= 140 else content[:137].rstrip() + "...")
    parts: List[str] = []
    if previous_summary:
        parts.append(previous_summary)
    if said:
        parts.append("The user said: " + " / ".join(said[-6:]))
    return clean_summary(" ".join(parts))
