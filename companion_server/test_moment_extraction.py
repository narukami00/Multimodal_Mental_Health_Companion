"""Tests for the moment extraction guard. No model is loaded."""

import asyncio

from llm_service import LlmService
from moment_extraction import (
    MAX_MOMENT_CHARS,
    extraction_messages,
    is_sensitive,
    validate_moment,
)

ORIGINAL = "Work was long. I had coffee with a friend and it was really nice. Tired now."
QUOTE = "I had coffee with a friend and it was really nice."


def test_a_faithful_quote_is_accepted():
    assert validate_moment(ORIGINAL, QUOTE) == QUOTE


def test_quotes_and_whitespace_are_tidied():
    assert validate_moment(ORIGINAL, '  "I had coffee with a friend and it was really nice."\n') == QUOTE


def test_none_and_junk_are_rejected():
    for bad in ["NONE", "none.", "", "   ", None, 42, ["x"]]:
        assert validate_moment(ORIGINAL, bad) is None


def test_the_model_may_not_reword_or_invent():
    assert validate_moment(ORIGINAL, "You had a wonderful time at the beach with your family.") is None
    assert validate_moment(ORIGINAL, "I had coffee with a friend and then I won the lottery today.") is None


def test_too_long_or_too_short_is_rejected():
    long_original = "I had a nice time " + "and then we walked " * 30
    assert validate_moment(long_original, long_original) is None
    assert len(QUOTE) <= MAX_MOMENT_CHARS
    assert validate_moment("Nice day out.", "Nice day out.") is None


def test_sensitive_topics_are_never_proposed_even_if_the_quote_is_clean():
    original = "My grandmother died last week. I had coffee with a friend and it was really nice."
    assert validate_moment(original, QUOTE) is None
    assert validate_moment(ORIGINAL, "I went to the hospital and the nurse was really nice.") is None


def test_sensitive_matching_is_by_whole_word():
    assert not is_sensitive("I saw my therapist and had a nice chat")
    assert is_sensitive("I felt dead tired")
    assert is_sensitive("thinking about suicide")


def test_prompt_asks_for_an_exact_quote():
    messages = extraction_messages("hello\n\nthere")
    assert "exactly as written" in messages[0]["content"]
    assert messages[1]["content"] == "hello there"


def test_extract_moment_uses_the_model_but_validates_it():
    class Fake(LlmService):
        @property
        def is_ready(self):
            return True

        reply = QUOTE

        async def generate_stream_async(self, messages, max_new_tokens=120):
            yield self.reply

    service = Fake()
    assert asyncio.run(service.extract_moment_async(ORIGINAL)) == QUOTE

    service.reply = "A completely made up sentence about something else entirely."
    assert asyncio.run(service.extract_moment_async(ORIGINAL)) is None

    service.reply = "NONE"
    assert asyncio.run(service.extract_moment_async(ORIGINAL)) is None


def test_extract_moment_without_a_model_is_none_not_an_error():
    assert asyncio.run(LlmService().extract_moment_async(ORIGINAL)) is None
