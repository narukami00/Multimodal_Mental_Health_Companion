"""Finding one good moment in something the person said, safely.

Pure helpers, no model import. The model is given the last few turns of the
conversation as well as the person's latest message, so that a reply such as
"that was a great idea" can be kept as what it was about ("Working is a great
idea"). It may only use words that appear in the conversation. Whatever it
returns is checked here: it must be short, made of words from the conversation
(mostly the person's own), free of sensitive topics, and not a vague fragment
that would mean nothing when read back later. If anything is off the answer is
thrown away, so the worst outcome is "no proposal".
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

MAX_INPUT_CHARS = 1200
MAX_MOMENT_CHARS = 140
MIN_OVERLAP = 0.8
MAX_CONTEXT_TURNS = 4
MAX_CONTEXT_CHARS = 240

EXTRACT_INSTRUCTION = (
    "You help someone keep the good moments of their life. Read their message and decide whether "
    "they describe something good that happened to them, or something they really enjoyed.\n"
    "If they do, copy the words that say it, exactly as written and without changing a single word: "
    "one or two sentences, at most 140 characters, that say WHAT happened and, when they say it, how it felt. "
    "Never start in the middle of a sentence.\n"
    "If they do not, answer null. Answer null when: nothing good happened; they did not enjoy it; the good word "
    "is sarcastic or negated; it is only praise that says nothing about what happened; or it is about illness, "
    "loss, money trouble or harm.\n"
    'Reply with JSON only: {"moment": "<their exact words>"} or {"moment": null}.\n'
    "Examples.\n"
    'Message: Tired today. The only nice part was lunch with Priya, we sat in the park and it was lovely.\n'
    '{"moment": "The only nice part was lunch with Priya, we sat in the park and it was lovely."}\n'
    "Message: I didn't enjoy the party at all, I just wanted to go home.\n"
    '{"moment": null}\n'
    "Message: That was so good, I loved it.\n"
    '{"moment": null}\n'
    "Message: I passed my driving test today! I'm so happy.\n"
    '{"moment": "I passed my driving test today! I\'m so happy."}'
)


def parse_extraction(raw: str) -> Optional[str]:
    """The words the model chose, from its JSON answer; None when it said null.

    Older or smaller models answer with plain text (or the word NONE) instead of JSON, so when there is no JSON
    object the text itself is returned and the checks in `validate_moment` decide.
    """
    text = (raw or "").strip()
    match = re.search(r"\{.*?\}", text, flags=re.DOTALL)
    if match is None:
        return text or None
    try:
        value = json.loads(match.group(0)).get("moment")
    except (ValueError, AttributeError):
        return None
    return value if isinstance(value, str) and value.strip() else None

# Used only when the message points back at something ("that was a great
# idea"). The model is not asked to write anything: only to copy a few words.
REFERENT_INSTRUCTION = (
    "Someone was talking, then replied with a short comment. Say what their "
    "comment is about by copying a few words from the earlier lines, exactly "
    "as written. If the lines before it include something Sol suggested or "
    "asked about, that is usually what it is about. Reply with only those "
    "words. If it is unclear, reply with the single word NONE.\n"
    "Example. Earlier lines: Them: I might start working again. / Sol: That "
    "could help. Their comment: That was a great idea. Answer: working again\n"
    "Example. Earlier lines: Sol: Would you like to take a short walk? Their "
    "comment: I loved that. Answer: a short walk\n"
    "Example. Earlier lines: Sol: How about calling a friend tonight? / Them: I might, "
    "I haven't spoken to anyone in days. Their comment: That was a good thought. "
    "Answer: calling a friend"
)

MAX_REFERENT_WORDS = 5
_CUT_AT = frozenset(
    "could would should might may must can will is are was were does do did has have "
    "sounds seems feels looks".split()
)

_WARM = re.compile(
    r"\b(good|great|nice|lovely|wonderful|amazing|awesome|happy|glad|fun|enjoy\w*|"
    r"proud|relieved|calm|better|lighter|love\w*|like[ds]?|perfect|brilliant|helped|helps)\b"
)
_FRAGMENT_STARTS = frozenset("which who whose and but because although though whereas".split())
# Praise word followed by a complaint ("Great, another meeting that could have been an email"): the good word is sarcasm.
_SARCASM = re.compile(
    r"\b(?:great|wonderful|perfect|fantastic|brilliant|lovely|nice|amazing)\b[,!.]*\s+(?:another|more of|just what)\b"
    r"|\byeah,? right\b|\boh,? (?:great|wonderful|perfect|fabulous)\b|\bcould have been an e-?mail\b|\bjust what i needed\b"
    r"|\bas if\b|\bthanks a lot\b"
)
_NEGATED = re.compile(r"\b(not|n't|never|no|nothing|without|don't|didn't|wasn't|isn't)\b")

_STOP = frozenset(
    "yeah yes yep yup sure indeed well oh wow haha ok okay "
    "a an the and or but so to of in on at for with from by as if than then "
    "i me my we us our you your he she they them their it its this that these those there here "
    "is am are was were be been being do does did done have has had having will would can could "
    "should may might must just really very too quite pretty also still even only not no yes "
    "what which who when where how why about into out up down over again more most some any all "
    # Contractions say as little as the words they shorten ("I'm happy with that" holds nothing to remember).
    "i'm i've i'd i'll it's that's there's here's he's she's we're we've we'd they're they've they'd you're you've you'd "
    "don't didn't isn't wasn't can't won't couldn't wouldn't".split()
)
# Words that say it was good, or that point at nothing in particular.
_VAGUE = frozenset(
    "good great nice lovely wonderful amazing awesome happy glad fun enjoy enjoyed enjoying "
    "proud relieved calm better lighter love loved like liked fine okay ok perfect "
    "idea ideas thing things day days time times stuff something anything everything one "
    "sound sounds sounded seem seems helped helps help".split()
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


def clean_context(raw: Any) -> List[Dict[str, str]]:
    """The last few turns before the message, as short plain lines.

    Accepts a list of {role, text} with role "user" or "assistant"; anything
    else is dropped. Newest last, at most MAX_CONTEXT_TURNS turns.
    """
    if not isinstance(raw, list):
        return []
    turns: List[Dict[str, str]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        text = item.get("text")
        if role not in ("user", "assistant") or not isinstance(text, str):
            continue
        line = " ".join(text.split())[:MAX_CONTEXT_CHARS]
        if line:
            turns.append({"role": role, "text": line})
    return turns[-MAX_CONTEXT_TURNS:]


def is_vague(line: str) -> bool:
    """True when a line says nothing that could be understood on its own.

    "That was a great idea." points at something it does not name, so read back
    in a later conversation it means nothing. A line is vague when, once filler
    words, praise words and empty nouns like "idea" or "thing" are taken away,
    nothing is left.
    """
    return not any(w not in _STOP and w not in _VAGUE for w in _words(line))


def extraction_messages(text: str) -> List[Dict[str, str]]:
    """The prompt that asks the model to copy one good sentence."""
    clipped = " ".join(text.split())[:MAX_INPUT_CHARS]
    return [
        {"role": "system", "content": EXTRACT_INSTRUCTION},
        {"role": "user", "content": clipped},
    ]


def referent_messages(
    text: str, context: Optional[List[Dict[str, str]]]
) -> List[Dict[str, str]]:
    """The prompt that asks the model to copy a few words naming what a short
    comment ("that was a great idea") is about."""
    clipped = " ".join(text.split())[:MAX_INPUT_CHARS]
    earlier = "\n".join(
        ("Them: " if t["role"] == "user" else "Sol: ") + t["text"]
        for t in clean_context(context)
    )
    return [
        {"role": "system", "content": REFERENT_INSTRUCTION},
        {"role": "user", "content": f"Earlier lines:\n{earlier}\n\nTheir comment:\n{clipped}"},
    ]


def topic_from_context(context: Optional[List[Dict[str, str]]]) -> Optional[str]:
    """What the conversation was just about, found without the model.

    The words Sol's last line shares with something the person said earlier are
    the topic both of them were on ("working", "walk by the river"). Returns the
    person's own wording of it, or None when they share nothing.
    """
    turns = clean_context(context)
    last_sol = next((t for t in reversed(turns) if t["role"] == "assistant"), None)
    users = [t for t in turns if t["role"] == "user"]
    if not last_sol or not users:
        return None
    topical = {w for w in _words(last_sol["text"]) if w not in _STOP and w not in _VAGUE}
    for turn in reversed(users):
        words = _words(turn["text"])
        hits = [i for i, w in enumerate(words) if w in topical]
        if not hits:
            continue
        span = words[hits[0] : hits[-1] + 1]
        if len(span) > MAX_REFERENT_WORDS:
            span = words[hits[0] : hits[0] + 1]
        phrase = " ".join(span)
        if phrase and not is_vague(phrase) and not is_sensitive(phrase):
            return phrase
    return None


def wants_referent(text: str) -> bool:
    """True when the message is a warm comment that does not say what about:
    some sentence has a praise word, is not negated, and is vague on its own."""
    for sentence in _sentences(text):
        lower = sentence.lower()
        if _WARM.search(lower) and not _NEGATED.search(lower) and is_vague(sentence):
            return True
    return False


def _sentences(text: str) -> List[str]:
    return [p.strip() for p in re.split(r"(?<=[.!?])\s+|\n+", text) if p.strip()]


def validate_referent(candidate: Any, context: Optional[List[Dict[str, str]]]) -> Optional[str]:
    """A few words copied from the earlier lines, or None.

    The words must appear, in order, in one of the earlier lines, so nothing can
    be invented; they must be two to six words, include a word that says
    something, and not be about a sensitive topic.
    """
    if not isinstance(candidate, str):
        return None
    phrase = " ".join(candidate.split()).strip(" \"'“”.,!?;:")
    if not phrase or phrase.upper() == "NONE":
        return None
    words = _words(phrase)
    # The model tends to copy a whole clause ("Working could give you some
    # structure"). Keep only the head: cut at the first helper verb, then trim
    # filler words from both ends, and cap the length.
    for i, w in enumerate(words):
        if i > 0 and w in _CUT_AT:
            words = words[:i]
            break
    while words and words[0] in _STOP:
        words.pop(0)
    while words and words[-1] in _STOP:
        words.pop()
    words = words[:MAX_REFERENT_WORDS]
    if not words or is_vague(" ".join(words)):
        return None
    wanted = " ".join(words)
    if is_sensitive(wanted):
        return None
    for turn in clean_context(context):
        if wanted in " ".join(_words(turn["text"])):
            return wanted
    return None


def compose_with_referent(referent: str, message: str) -> Optional[str]:
    """"About working again: That was a great idea." Built here, from the
    copied referent and the person's own sentence, so the model never writes the
    memory itself."""
    for sentence in _sentences(message):
        lower = sentence.lower()
        if _WARM.search(lower) and not _NEGATED.search(lower) and is_vague(sentence):
            line = f"About {referent}: {sentence}"
            return line if len(line) <= MAX_MOMENT_CHARS else None
    return None


def validate_moment(
    original: str,
    candidate: Any,
    context: Optional[List[Dict[str, str]]] = None,
) -> Optional[str]:
    """The candidate as a single clean line, or None if it is not acceptable.

    Acceptable means: a non-empty single line within the length cap, not the
    model saying NONE, not about a sensitive topic (in the candidate, the
    message *or* the earlier turns), not vague, and made of words from the
    conversation: at least 80% of its words appear in the message or the earlier
    turns, and at least two of them in the person's own message, so the line is
    always about something they actually said.
    """
    if not isinstance(candidate, str):
        return None
    line = " ".join(candidate.split()).strip(" \"'“”")
    if not line or line.upper().rstrip(".") == "NONE":
        return None
    if len(line) > MAX_MOMENT_CHARS:
        return None
    turns = clean_context(context)
    if is_sensitive(line) or is_sensitive(original):
        return None
    if _SARCASM.search(line.lower()) or _SARCASM.search(original.lower()):
        return None
    if any(is_sensitive(t["text"]) for t in turns):
        return None
    # "About working again: ..." is built in code; its lead word is not theirs.
    mine = _words(re.sub(r"^about\b", "", line, flags=re.IGNORECASE))
    if len(mine) < 4:
        return None
    # Starting mid-sentence ("which felt really good.") is a fragment that cannot be read back later.
    if mine[0] in _FRAGMENT_STARTS:
        return None
    if is_vague(line):
        return None
    theirs = set(_words(original))
    known = theirs.union(*(set(_words(t["text"])) for t in turns)) if turns else theirs
    if re.match(r"^about\b", line, flags=re.IGNORECASE) and ":" in line:
        # The topic is the one part that is not the person's sentence, so every
        # word of it must come from the conversation: no tolerance.
        topic = _words(line.split(":", 1)[0])[1:]
        if not topic or any(w not in known for w in topic):
            return None
    overlap = sum(1 for w in mine if w in known) / len(mine)
    if overlap < MIN_OVERLAP:
        return None
    if sum(1 for w in set(mine) if w in theirs) < 2:
        return None
    return line
