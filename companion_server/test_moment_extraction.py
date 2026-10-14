"""Tests for the moment extraction guard. No model is loaded."""

import asyncio

from llm_service import LlmService
from llm_service import rank_memory_facts
from moment_extraction import (
    MAX_MOMENT_CHARS,
    clean_context,
    compose_with_referent,
    extraction_messages,
    is_sensitive,
    is_vague,
    referent_messages,
    topic_from_context,
    validate_moment,
    validate_referent,
    wants_referent,
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


def test_the_copy_prompt_asks_for_an_exact_quote():
    messages = extraction_messages("hello\n\nthere")
    assert "exactly as written" in messages[0]["content"]
    assert messages[1]["content"] == "hello there"


CONTEXT = [
    {"role": "user", "text": "I might start working again, maybe part time."},
    {"role": "assistant", "text": "Working could give you some structure. How does that sound?"},
]


def test_the_referent_prompt_carries_the_earlier_turns():
    content = referent_messages("That was a great idea.", CONTEXT)[1]["content"]
    assert "Them: I might start working again" in content
    assert "Sol: Working could give you some structure" in content
    assert content.endswith("Their comment:\nThat was a great idea.")


def test_what_the_conversation_was_about_is_found_without_the_model():
    # The reported bug: "that was a great idea" was kept as exactly that, with
    # no hint of what the idea was.
    assert topic_from_context(CONTEXT) == "working"
    walk = [
        {"role": "assistant", "text": "Maybe you could take a short walk by the river this evening."},
        {"role": "user", "text": "I went for a walk by the river"},
    ]
    assert topic_from_context(walk) == "walk by the river"
    assert topic_from_context([{"role": "assistant", "text": "Try a walk?"}]) is None
    assert topic_from_context(None) is None


def test_the_memory_is_composed_in_code_from_the_topic_and_their_own_words():
    line = compose_with_referent("working", "That was a great idea.")
    assert line == "About working: That was a great idea."
    assert validate_moment("That was a great idea.", line, CONTEXT) == line
    # a negated or empty comment is never composed into a memory
    assert compose_with_referent("working", "That was not a great idea.") is None
    assert compose_with_referent("working", "Okay then.") is None


def test_only_warm_comments_that_say_nothing_on_their_own_want_a_topic():
    assert wants_referent("That was a great idea.")
    assert wants_referent("sounds great to me")
    assert not wants_referent("That was not a great idea.")
    assert not wants_referent("I had coffee with a friend and it was really nice.")
    assert not wants_referent("ok")


def test_a_referent_copied_by_the_model_is_trimmed_and_checked_against_the_lines():
    ctx = [{"role": "assistant", "text": "Working could give you some structure."}]
    assert validate_referent("Working could give you some structure", ctx) == "working"
    assert validate_referent("Moving to Paris", ctx) is None  # not in the lines
    assert validate_referent("NONE", ctx) is None
    assert validate_referent("They liked it.", ctx) is None
    assert validate_referent(None, ctx) is None


def test_a_vague_line_is_never_kept_even_if_quoted_faithfully():
    assert is_vague("That was a great idea.")
    assert is_vague("It was so nice.")
    assert is_vague("sounds great to me")
    assert validate_moment("That was a great idea.", "That was a great idea.", CONTEXT) is None
    assert validate_moment("That was a great idea.", "That was a great idea.") is None
    assert not is_vague("Working is a great idea.")
    assert not is_vague(QUOTE)


def test_context_cannot_smuggle_in_an_invention():
    assert validate_moment("That was a great idea.", "About Paris: That was a great idea.", CONTEXT) is None


def test_the_line_must_be_about_what_they_actually_said():
    # Every word is in the earlier turns, but none are in the person's message.
    assert validate_moment("Okay.", "Working could give you some structure.", CONTEXT) is None


def test_sensitive_context_blocks_the_proposal():
    hard = CONTEXT + [{"role": "user", "text": "My grandmother died and working helps."}]
    assert validate_moment("That was a great idea.", "About working: That was a great idea.", hard) is None


def test_the_whole_pipeline_with_a_model_that_only_copies_words():
    class Fake(LlmService):
        @property
        def is_ready(self):
            return True

        replies = []

        async def generate_stream_async(self, messages, max_new_tokens=120, temperature=0.7, top_p=0.9):
            yield self.replies.pop(0)

    service = Fake()
    # step 1 copies the vague sentence (refused), the topic is found in code
    service.replies = ["That was a great idea."]
    assert (
        asyncio.run(service.extract_moment_async("That was a great idea.", CONTEXT))
        == "About working: That was a great idea."
    )
    # no shared topic: the model names it by copying words from Sol's line
    lonely = [{"role": "assistant", "text": "Would you like to try a five minute breathing exercise?"}]
    service.replies = ["sounds great to me", "breathing exercise"]
    assert (
        asyncio.run(service.extract_moment_async("sounds great to me", lonely))
        == "About breathing exercise: sounds great to me"
    )
    # a model that makes something up is refused, so nothing is kept
    service.replies = ["That was a great idea.", "Moving to Paris"]
    assert asyncio.run(service.extract_moment_async("That was a great idea.", lonely)) is None
    # no earlier lines: a bare vague comment is never kept
    service.replies = ["That was a great idea."]
    assert asyncio.run(service.extract_moment_async("That was a great idea.", [])) is None


def test_context_is_cleaned_and_capped():
    raw = [{"role": "user", "text": "a " * 500}, {"role": "system", "text": "x"}, 5, None] + [
        {"role": "assistant", "text": f"line {i}"} for i in range(6)
    ]
    cleaned = clean_context(raw)
    assert len(cleaned) == 4
    assert all(t["role"] in ("user", "assistant") for t in cleaned)
    assert clean_context("nope") == []


def test_kept_moments_that_match_what_was_said_come_first():
    memory = {"profile_snippet": "", "memory_facts": ["Tea with my sister.", "Working is a great idea.", "A walk by the river."]}
    ranked = rank_memory_facts(memory, "I am thinking about working again")
    assert ranked["memory_facts"][0] == "Working is a great idea."
    assert sorted(ranked["memory_facts"]) == sorted(memory["memory_facts"])
    # nothing to match on: order unchanged
    assert rank_memory_facts(memory, "ok")["memory_facts"] == memory["memory_facts"]
    assert rank_memory_facts(None, "work") is None


def test_extract_moment_uses_the_model_but_validates_it():
    class Fake(LlmService):
        @property
        def is_ready(self):
            return True

        reply = QUOTE

        async def generate_stream_async(self, messages, max_new_tokens=120, temperature=0.7, top_p=0.9):
            yield self.reply

    service = Fake()
    assert asyncio.run(service.extract_moment_async(ORIGINAL)) == QUOTE

    service.reply = "A completely made up sentence about something else entirely."
    assert asyncio.run(service.extract_moment_async(ORIGINAL)) is None

    service.reply = "NONE"
    assert asyncio.run(service.extract_moment_async(ORIGINAL)) is None


def test_extract_moment_without_a_model_is_none_not_an_error():
    assert asyncio.run(LlmService().extract_moment_async(ORIGINAL)) is None
