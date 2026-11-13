"""User facts extraction, validation, and selective BM25 + semantic retrieval.

Pure Python helpers with zero heavy ML dependencies so CI, benchmarks, and
horizontal replicas remain fast and deterministic. Extracted facts are strictly
grounded in `role == "user"` conversation turns (preventing system-prompt or
assistant-suggestion leakage) and filtered for safety and prompt injection.
"""

from __future__ import annotations

import json
import math
import re
from typing import Any, Dict, List, Optional, Sequence, Tuple

from moment_extraction import _STOP as STOP_WORDS, _words as extract_words, is_sensitive

MAX_USER_FACTS = 4
MAX_USER_FACTS_CANDIDATES = 32
MAX_USER_FACT_CHARS = 120
MAX_IDENTITY_SUMMARY_CHARS = 240
MAX_USER_FACTS_BUDGET_CHARS = 340

# 12 domain clusters for zero-embedding semantic recall on constrained hosts.
SEMANTIC_CLUSTERS: Tuple[Tuple[str, ...], ...] = (
    ("sleep", "sleeping", "slept", "insomnia", "tired", "exhausted", "drained", "fatigue", "rest", "nap", "night", "awake", "bedtime"),
    ("work", "job", "office", "boss", "coworker", "colleague", "deadline", "project", "meeting", "busy", "overworked", "internship", "shift"),
    ("study", "studies", "studying", "student", "university", "college", "exam", "exams", "finals", "midterm", "class", "classes", "assignment", "thesis", "grade", "grades", "degree", "cs"),
    ("stress", "stressed", "anxious", "anxiety", "worried", "worry", "overwhelmed", "panic", "tense", "pressure", "nervous", "burnout"),
    ("sad", "low", "heavy", "down", "lonely", "alone", "cry", "crying", "empty", "hopeless", "hurt", "grief"),
    ("people", "family", "mom", "mother", "dad", "father", "parents", "sister", "brother", "sibling", "friend", "friends", "partner", "roommate", "relationship"),
    ("pets", "dog", "cat", "pet", "pets", "puppy", "kitten", "vet", "walked"),
    ("calm", "breathe", "breathing", "grounding", "walk", "walking", "outside", "outdoors", "journal", "quiet", "unwind", "tea", "coffee", "rain"),
    ("hobbies", "music", "guitar", "piano", "reading", "book", "books", "game", "gaming", "cooking", "bake", "baking", "drawing", "art", "run", "running", "gym"),
    ("health", "headache", "migraine", "sick", "fever", "appetite", "meal", "eat", "eating", "water", "hydrate", "exercise"),
    ("home", "apartment", "dorm", "hostel", "room", "commute", "bus", "train", "traffic", "move", "moving", "city", "hometown"),
    ("goals", "habit", "routine", "morning", "evening", "schedule", "plan", "focus", "procrastinating", "procrastinate"),
)

CLUSTER_BY_WORD: Dict[str, int] = {
    word: idx
    for idx, cluster in enumerate(SEMANTIC_CLUSTERS)
    for word in cluster
}

_INSTRUCTION_RE = re.compile(
    r"\b(ignore\s+previous|system\s+prompt|jailbreak|always\s+reply|pretend\s+to\s+be|"
    r"you\s+must|override|instructions?)\b",
    re.IGNORECASE,
)

# Common verbs/pronouns that carry little personal grounding signal.
_WEAK_FACT_WORDS = STOP_WORDS | frozenset(
    "has have had got gets is are was were am be been being can could would should "
    "like likes prefer prefers enjoy enjoys loves love lives live works work studies "
    "study feels feel using uses user they them their person someone named called".split()
)

FACT_EXTRACTION_INSTRUCTION = (
    "You extract durable, non-clinical personal facts from a conversation so a companion remembers who they are.\n"
    "Read ONLY what the USER actually stated about themselves (name, studies/work, pets, living situation, family/friends, hobbies, routines, clear preferences).\n"
    "Rules:\n"
    "- Return concise atomic facts in short third-person style without 'The user' bloat (e.g., 'Has a dog named Milo', 'Studies computer science', 'Prefers herbal tea at night').\n"
    "- NEVER include assistant suggestions, temporary feelings ('felt tired today'), clinical diagnoses, medical/crisis topics, or guesses.\n"
    "- Do NOT repeat facts already listed under Existing Facts.\n"
    "- Return at most 4 short facts, each under 100 characters.\n"
    'Reply ONLY with strict JSON: {"facts": ["..."]} or {"facts": []}.'
)

IDENTITY_SUMMARY_INSTRUCTION = (
    "Write a warm, compact 1 to 3 sentence background note summarizing these facts about one person.\n"
    "Rules:\n"
    "- Refer to them naturally ('They ...').\n"
    "- Keep it concise (under 220 characters total), plain prose only, no bullet points, no markdown, and no invented details.\n"
    "- Only state facts present in the list."
)


def _clean_single_line(value: Any, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    cleaned = "".join(ch if ch >= " " or ch == "\t" else " " for ch in value)
    cleaned = " ".join(cleaned.split())
    return cleaned[:limit].strip()


def _turn_text(turn: Any) -> str:
    if not isinstance(turn, dict):
        return ""
    raw = turn.get("content")
    if not isinstance(raw, str) or not raw.strip():
        raw = turn.get("text")
    return raw if isinstance(raw, str) else ""


def semantic_tokens(text: str) -> Tuple[set[str], set[int]]:
    """Return meaningful lowercase words and matched semantic topic cluster IDs."""
    words = {w for w in extract_words(text) if w not in STOP_WORDS and len(w) > 1}
    clusters = {CLUSTER_BY_WORD[w] for w in words if w in CLUSTER_BY_WORD}
    return words, clusters


def rank_selective_items(
    items: Sequence[str],
    query: str,
    *,
    pinned_count: int = 0,
    recency_scores: Optional[Sequence[float]] = None,
    top_k: Optional[int] = None,
    max_chars: Optional[int] = None,
) -> List[str]:
    """Rank items using BM25-style IDF word overlap + semantic clusters + recency,
    while keeping `pinned_count` leading items protected and packing within budgets."""
    n = len(items)
    if n == 0:
        return []

    raw_pinned = max(0, min(pinned_count, n))
    q_words, q_clusters = semantic_tokens(query)

    # Pre-tokenize all items once so we can compute IDF weights across the pool.
    tokenized = [semantic_tokens(item) for item in items]
    df: Dict[str, int] = {}
    for words, _ in tokenized:
        for w in words:
            df[w] = df.get(w, 0) + 1

    def _idf(w: str) -> float:
        freq = df.get(w, 0)
        return math.log((n + 1.0) / (freq + 0.5)) + 1.0

    def _score_slice(indices: Sequence[int]) -> List[Tuple[int, float, str]]:
        if not q_words and not q_clusters:
            return [
                (
                    i,
                    float(recency_scores[i]) if recency_scores and i < len(recency_scores) else 0.0,
                    items[i],
                )
                for i in indices
            ]

        scored: List[Tuple[float, float, int, str]] = []
        for i in indices:
            i_words, i_clusters = tokenized[i]
            exact_hits = q_words & i_words
            bm25_exact = sum(_idf(w) * 1.6 for w in exact_hits)
            cluster_hits = len(q_clusters & i_clusters) * 1.1
            rec = (
                max(0.0, min(1.0, float(recency_scores[i]))) * 0.35
                if recency_scores and i < len(recency_scores)
                else 0.0
            )
            relevance = bm25_exact + cluster_hits + rec
            scored.append((-relevance, -rec, i, items[i]))
        scored.sort()
        return [(i, -rel, text) for rel, _, i, text in scored]

    pinned_ranked = [text for _, _, text in _score_slice(range(0, raw_pinned))] if raw_pinned > 0 else []
    rest_ranked = [text for _, _, text in _score_slice(range(raw_pinned, n))]
    ordered = pinned_ranked + rest_ranked

    if top_k is not None:
        ordered = ordered[: max(0, top_k)]
    if max_chars is not None and max_chars > 0:
        packed: List[str] = []
        used = 0
        for item in ordered:
            cost = len(item) + (2 if packed else 0)
            if packed and used + cost > max_chars:
                break
            packed.append(item)
            used += cost
        ordered = packed
    return ordered


def _jaccard_words(a: str, b: str) -> float:
    wa = {w for w in extract_words(a) if w not in _WEAK_FACT_WORDS}
    wb = {w for w in extract_words(b) if w not in _WEAK_FACT_WORDS}
    if not wa or not wb:
        return 0.0
    return len(wa & wb) / len(wa | wb)


def parse_extracted_facts(raw: str) -> List[str]:
    """Parse strict `{"facts": [...]}` JSON from LLM output safely."""
    text = (raw or "").strip()
    if not text:
        return []
    match = re.search(r"\{.*\}", text, flags=re.DOTALL)
    if not match:
        return []
    try:
        data = json.loads(match.group(0))
    except (ValueError, TypeError):
        return []
    facts = data.get("facts") if isinstance(data, dict) else None
    if not isinstance(facts, list):
        return []
    return [f for f in facts if isinstance(f, str)]


def validate_extracted_facts(
    candidates: Sequence[str],
    turns: Sequence[Dict[str, str]],
    existing_facts: Optional[Sequence[str]] = None,
    max_new: int = 4,
) -> List[str]:
    """Keep only safe, non-duplicate atomic facts grounded in `role == 'user'` turns."""
    user_text = " ".join(
        _turn_text(t)
        for t in turns
        if isinstance(t, dict) and t.get("role") == "user"
    )
    user_vocab = {w for w in extract_words(user_text) if len(w) > 1}
    if not user_vocab:
        return []

    seen: List[str] = [
        _clean_single_line(f, MAX_USER_FACT_CHARS)
        for f in (existing_facts or ())
        if isinstance(f, str) and f.strip()
    ]
    accepted: List[str] = []

    for raw in candidates:
        line = _clean_single_line(raw, MAX_USER_FACT_CHARS)
        if len(line) < 8:
            continue
        if _INSTRUCTION_RE.search(line) or is_sensitive(line):
            continue
        content_words = [
            w for w in extract_words(line)
            if w not in _WEAK_FACT_WORDS and len(w) > 1
        ]
        if not content_words:
            continue
        # Grounding check: at least half of meaningful words must come from what
        # the USER actually wrote in this conversation (prevents assistant/prompt leak).
        grounded = sum(1 for w in content_words if w in user_vocab)
        if grounded == 0 or (grounded / len(content_words)) < 0.5:
            continue
        # Normalize minor leading prefixes like "They " / "The user " cleanly.
        line = re.sub(r"^(the user|user)\s+", "", line, flags=re.IGNORECASE).strip()
        if len(line) < 8:
            continue
        line = line[0].upper() + line[1:]
        if any(_jaccard_words(line, prev) >= 0.55 or line.lower() == prev.lower() for prev in seen + accepted):
            continue
        accepted.append(line)
        if len(accepted) >= max_new:
            break

    return accepted


def fact_extraction_messages(
    turns: Sequence[Dict[str, str]],
    existing_facts: Optional[Sequence[str]] = None,
) -> List[Dict[str, str]]:
    """Build prompt messages showing ONLY sanitized user turns + existing facts."""
    user_lines = []
    for t in turns[-24:]:
        if isinstance(t, dict) and t.get("role") == "user":
            line = _clean_single_line(_turn_text(t), 320)
            if line:
                user_lines.append(f"- {line}")
    existing_lines = [
        _clean_single_line(f, MAX_USER_FACT_CHARS)
        for f in (existing_facts or ())[:MAX_USER_FACTS_CANDIDATES]
        if isinstance(f, str) and f.strip()
    ]
    parts = ["User messages from this conversation:"]
    parts.extend(user_lines or ["(none)"])
    if existing_lines:
        parts.append("")
        parts.append("Existing Facts (do not repeat):")
        parts.extend(f"- {f}" for f in existing_lines)
    return [
        {"role": "system", "content": FACT_EXTRACTION_INSTRUCTION},
        {"role": "user", "content": "\n".join(parts)},
    ]


def identity_summary_messages(facts: Sequence[str]) -> List[Dict[str, str]]:
    """Prompt messages to compile atomic user facts into a compact portrait."""
    clean_facts = [
        _clean_single_line(f, MAX_USER_FACT_CHARS)
        for f in facts[:12]
        if isinstance(f, str) and f.strip()
    ]
    body = "Known facts:\n" + "\n".join(f"- {f}" for f in clean_facts)
    return [
        {"role": "system", "content": IDENTITY_SUMMARY_INSTRUCTION},
        {"role": "user", "content": body},
    ]


def clean_identity_summary(raw: Any) -> str:
    """Validate an LLM-generated identity summary against safety and length bounds."""
    text = _clean_single_line(raw, MAX_IDENTITY_SUMMARY_CHARS)
    if not text or len(text) < 12:
        return ""
    if _INSTRUCTION_RE.search(text) or is_sensitive(text):
        return ""
    return text


def fallback_identity_summary(facts: Sequence[str]) -> str:
    """Deterministic fallback summary when no LLM is available."""
    cleaned = [
        _clean_single_line(f, MAX_USER_FACT_CHARS).rstrip(".")
        for f in facts[:4]
        if isinstance(f, str) and f.strip()
    ]
    if not cleaned:
        return ""
    if len(cleaned) == 1:
        text = cleaned[0] + "."
    else:
        text = "; ".join(cleaned[:-1]) + "; and " + cleaned[-1] + "."
    return text[:MAX_IDENTITY_SUMMARY_CHARS].strip()


def estimate_prompt_savings(
    total_user_facts: int,
    selected_user_facts: int,
    all_facts_chars: int,
    selected_facts_chars: int,
) -> Dict[str, Any]:
    """Compute approximate character and token savings from selective memory retrieval."""
    saved_chars = max(0, all_facts_chars - selected_facts_chars)
    approx_saved_tokens = (saved_chars + 3) // 4
    reduction_pct = (saved_chars / all_facts_chars * 100.0) if all_facts_chars > 0 else 0.0
    return {
        "total_facts": total_user_facts,
        "selected_facts": selected_user_facts,
        "saved_chars": saved_chars,
        "approx_saved_tokens": approx_saved_tokens,
        "reduction_pct": round(reduction_pct, 1),
    }
