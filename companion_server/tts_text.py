"""Makes text easy to say aloud: numbers, money (taka and others), lakh and crore, times, percentages, short forms and names.

Speech engines read "Tk 250" or "1,00,000" badly or not at all. `normalize_for_speech` spells such things out the way a person would say
them, and `split_clauses` cuts a reply into clauses so a voice can pause between them. Pure functions, no model, no network.

Names the voice gets wrong can be fixed without code: put them in a JSON file {"Rafsan": "Raf-sahn"} and point SOLACE_TTS_PRONUNCIATIONS at it.
"""
from __future__ import annotations

import json
import os
import re
from functools import lru_cache
from typing import Dict, List, Optional, Tuple

_ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen",
         "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
_TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
_ORDINALS = {"one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth", "twelve": "twelfth"}

_CURRENCIES = {"tk": "taka", "taka": "taka", "bdt": "taka", "৳": "taka", "$": "dollars", "usd": "dollars", "£": "pounds",
               "gbp": "pounds", "€": "euros", "eur": "euros", "₹": "rupees", "rs": "rupees", "inr": "rupees", "rupees": "rupees"}
_ABBREVIATIONS = [(r"\bDr\.", "Doctor"), (r"\bMr\.", "Mister"), (r"\bMrs\.", "Missus"), (r"\bvs\.?(?=\s)", "versus"),
                  (r"\betc\.", "and so on"), (r"\be\.g\.", "for example"), (r"\bi\.e\.", "that is"), (r"\bapprox\.", "approximately")]


def _below_hundred(n: int) -> str:
    if n < 20:
        return _ONES[n]
    tens, ones = divmod(n, 10)
    return _TENS[tens] + (f" {_ONES[ones]}" if ones else "")


def _below_thousand(n: int) -> str:
    hundreds, rest = divmod(n, 100)
    parts = []
    if hundreds:
        parts.append(f"{_ONES[hundreds]} hundred")
    if rest:
        parts.append(_below_hundred(rest))
    return " ".join(parts)


def number_to_words(n: int, south_asian: bool = False) -> str:
    """204 -> 'two hundred four'. With [south_asian], 100000 -> 'one lakh' and 12000000 -> 'one crore two lakh'."""
    if n < 0:
        return "minus " + number_to_words(-n, south_asian)
    if n < 100:
        return _below_hundred(n)
    if south_asian and n >= 100_000:
        crore, rest = divmod(n, 10_000_000)
        lakh, rest = divmod(rest, 100_000)
        parts = []
        if crore:
            parts.append(f"{number_to_words(crore, True)} crore")
        if lakh:
            parts.append(f"{_below_hundred(lakh)} lakh")
        if rest:
            parts.append(number_to_words(rest))
        return " ".join(parts)
    parts = []
    for size, name in ((1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand")):
        chunk, n = divmod(n, size)
        if chunk:
            parts.append(f"{_below_thousand(chunk)} {name}")
    if n:
        parts.append(_below_thousand(n))
    return " ".join(parts)


def _digits(text: str) -> str:
    return " ".join(_ONES[int(d)] for d in text)


# 1,00,000 and 12,34,567: groups of two after the last three digits. Written this way it is said "lakh" and "crore".
_INDIAN_GROUPING = re.compile(r"\d{1,2}(?:,\d{2})+,\d{3}")


def _number_text(raw: str) -> str:
    """'5,000' -> 'five thousand'; '2.5' -> 'two point five'; '1,00,000' -> 'one lakh'."""
    whole, _, fraction = raw.partition(".")
    plain = whole.replace(",", "")
    if not plain:
        return raw
    spoken = number_to_words(int(plain), south_asian=bool(_INDIAN_GROUPING.fullmatch(whole)))
    return f"{spoken} point {_digits(fraction)}" if fraction else spoken


def _ordinal(n: int) -> str:
    words = number_to_words(n)
    last = words.split(" ")[-1]
    if last in _ORDINALS:
        return words[: len(words) - len(last)] + _ORDINALS[last]
    if last.endswith("y"):
        return words[:-1] + "ieth"
    return words + "th"


_MONEY = re.compile(
    r"(?:(?P<pre>[৳$£€₹]|\b(?:tk|bdt|usd|gbp|eur|rs|inr)\b\.?)\s?(?P<num>\d[\d,]*(?:\.\d+)?)(?:\s(?P<scale>lakhs?|crores?|k)\b)?"
    r"|(?P<num2>\d[\d,]*(?:\.\d+)?)\s(?P<post>taka|bdt|tk|usd|rupees)\b)",
    flags=re.IGNORECASE,
)
_PERCENT = re.compile(r"(\d[\d,]*(?:\.\d+)?)\s?%")
_TIME = re.compile(r"\b(\d{1,2}):(\d{2})\s?(am|pm)?\b", flags=re.IGNORECASE)
_ORDINAL = re.compile(r"\b(\d{1,3})(?:st|nd|rd|th)\b")
_SCALE_WORDS = re.compile(r"\b(\d[\d,]*(?:\.\d+)?)\s(lakhs?|crores?)\b", flags=re.IGNORECASE)
_NUMBER = re.compile(r"\b\d[\d,]*(?:\.\d+)?\b")
_YEAR = re.compile(r"\b(in|since|year|from|until|by|of)\s(1[5-9]\d\d|20[1-9]\d)\b", flags=re.IGNORECASE)


def _money_sub(match: re.Match) -> str:
    if match.group("pre"):
        symbol, raw, scale = match.group("pre").rstrip("."), match.group("num"), match.group("scale")
    else:
        symbol, raw, scale = match.group("post"), match.group("num2"), None
    amount = _number_text(raw)
    if scale:
        amount += " thousand" if scale.lower() == "k" else f" {scale.lower().rstrip('s')}"
    return f"{amount} {_CURRENCIES.get(symbol.lower(), symbol)}"


def _time_sub(match: re.Match) -> str:
    hour, minute, ampm = int(match.group(1)), int(match.group(2)), match.group(3)
    if minute == 0:
        return f"{_below_hundred(hour)} {ampm.upper()}" if ampm else f"{_below_hundred(hour)} o'clock"
    spoken_minute = f"oh {_below_hundred(minute)}" if minute < 10 else _below_hundred(minute)
    return f"{_below_hundred(hour)} {spoken_minute}" + (f" {ampm.upper()}" if ampm else "")


def _year_sub(match: re.Match) -> str:
    year = int(match.group(2))
    high, low = divmod(year, 100)
    spoken_low = "hundred" if low == 0 else (f"oh {_below_hundred(low)}" if low < 10 else _below_hundred(low))
    return f"{match.group(1)} {_below_hundred(high)} {spoken_low}"


@lru_cache(maxsize=1)
def _pronunciations() -> Dict[str, str]:
    path = os.environ.get("SOLACE_TTS_PRONUNCIATIONS")
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return {str(k): str(v) for k, v in data.items()} if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def normalize_for_speech(text: str, pronunciations: Optional[Dict[str, str]] = None) -> str:
    """The text as it should be said: numbers, money, times and short forms spelled out; markdown and emoji removed."""
    out = text
    # Markdown marks and emoji are never said.
    out = re.sub(r"[*_`#>~]+", "", out)
    out = re.sub("[\U0001F000-\U0001FAFF☀-➿️]", "", out)
    for pattern, spoken in _ABBREVIATIONS:
        out = re.sub(pattern, spoken, out)
    out = _MONEY.sub(_money_sub, out)
    out = _SCALE_WORDS.sub(lambda m: f"{_number_text(m.group(1))} {m.group(2).lower().rstrip('s')}", out)
    out = _PERCENT.sub(lambda m: f"{_number_text(m.group(1))} percent", out)
    out = _TIME.sub(_time_sub, out)
    out = _ORDINAL.sub(lambda m: _ordinal(int(m.group(1))), out)
    out = _YEAR.sub(_year_sub, out)
    out = _NUMBER.sub(lambda m: _number_text(m.group(0)), out)
    for written, spoken in {**_pronunciations(), **(pronunciations or {})}.items():
        out = re.sub(rf"\b{re.escape(written)}\b", spoken, out)
    return re.sub(r"[ \t]+", " ", out).strip()


_CLAUSE_END = re.compile(r"(?<=[,;:.!?])\s+")


def split_clauses(text: str) -> List[Tuple[str, str]]:
    """The text as (clause, closing mark) pairs so a voice can pause by the mark; very short pieces join the next clause."""
    pieces = [p.strip() for p in _CLAUSE_END.split(text.strip()) if p.strip()]
    clauses: List[Tuple[str, str]] = []
    carry = ""
    for piece in pieces:
        mark = piece[-1] if piece[-1] in ",;:.!?" else "."
        body = (carry + " " + piece).strip() if carry else piece
        if len(re.sub(r"[^A-Za-z]", "", body)) < 4:
            carry = body
            continue
        clauses.append((body, mark))
        carry = ""
    if carry:
        clauses.append((carry, "."))
    return clauses
