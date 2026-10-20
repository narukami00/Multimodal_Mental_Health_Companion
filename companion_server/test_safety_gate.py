"""Tests for the crisis-language gate (safety_gate.py) and its place in session.Session (no GPU, no network).

What must hold: crisis language is caught WITHOUT the emotion service (off, absent or dead), the language model is not asked, the
app gets a level (never the words), no emotion cue follows for this and the next few turns, and the user's words are not logged.
Run: python -m pytest test_safety_gate.py
"""
import logging

import pytest

import safety_gate
from test_emotion_session import CUE, CueLlm, FakeEmotion, opt_in, result, with_emotion
from test_session_logic import Call

URGENT_PHRASES = [
    "I will kill myself.", "I'm going to end my life", "Sometimes I want to die", "I wanna die", "I just want to end my own life.",
    "I keep thinking about suicide", "I feel suicidal", "i don’t want to be here anymore", "I dont want to live like this",
    "They'd be better off without me", "everyone would be better off dead", "I wish I were dead", "I wish I was dead",
    "I have been hurting myself", "I want to hurt myself", "thinking about self-harm", "self harm again today", "I might harm myself",
    "I can't see any reason to live", "there is no reason to live", "I'm not safe with myself tonight", "Take my own life, that's what I think about",
    "I.WANT.TO.DIE", "I WANT TO KILL MYSELF", "i am killing myself slowly", "I was thinking of ending my life",
    "Honestly I don't want to be alive", "I wanted to die yesterday", "I think about taking my own life", "selfharm",
]
BENIGN_PHRASES = [
    "I had a long day at work.", "The meeting is at three.", "I feel tired and a bit low.", "I am so happy today!", "I'm worried about my exam",
    "My sister is coming to visit", "I couldn't sleep well", "I'm nervous about tomorrow", "Can you recommend a calming exercise?",
    "I killed it at the presentation", "This traffic is killing my mood",
]


@pytest.mark.parametrize("text", URGENT_PHRASES)
def test_every_urgent_phrase_is_caught(text):
    assert safety_gate.assess(text) == safety_gate.URGENT


@pytest.mark.parametrize("text", BENIGN_PHRASES)
def test_ordinary_sentences_are_not_flagged(text):
    assert safety_gate.assess(text) is None


@pytest.mark.parametrize("text", ["I feel hopeless", "I had a panic attack today", "I'm completely overwhelmed", "I am not safe"])
def test_support_level(text):
    assert safety_gate.assess(text) == safety_gate.SUPPORT


@pytest.mark.asyncio
async def test_typed_crisis_text_gets_the_fixed_reply_without_any_emotion_service():
    async with Call(["unused"]) as call:  # no emotion service attached and no emotion opt-in at all
        call.ws.put_json({"type": "text_message", "turn_id": "t1", "text": "I want to die."})
        await call.until("tts.end")
        alert = call.ws.of("safety.alert")[0]
        assert alert["level"] == "urgent_support" and alert["turn_id"] == "t1" and "die" not in str(alert)
        assert call.ws.of("llm_done")[0]["text"] == safety_gate.crisis_reply()
        assert call.llm.prompts == []  # the language model was never asked


@pytest.mark.asyncio
async def test_spoken_crisis_turn_is_caught_even_when_the_emotion_service_is_dead():
    async with Call(["I will kill myself."]) as call:
        with_emotion(call, FakeEmotion(None), CueLlm())  # every call fails, like a down service
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        assert call.ws.of("safety.alert")[0]["level"] == "urgent_support"
        assert call.ws.of("llm_done")[0]["text"] == safety_gate.crisis_reply(spoken=True)  # voice turns get the spoken wording
        assert call.ws.of("tts.end")[0]["cancelled"] is False  # the fixed text was spoken too


@pytest.mark.asyncio
async def test_no_emotion_cue_for_the_crisis_turn_and_the_next_three():
    async with Call(["unused"]) as call:
        llm = CueLlm()
        with_emotion(call, FakeEmotion(result()), llm)
        await opt_in(call)
        texts = ["I want to die.", "ok", "I am just tired", "still tired", "so tired of everything"]
        for i, text in enumerate(texts):
            call.ws.put_json({"type": "text_message", "turn_id": f"t{i}", "text": text})
            await call.until("llm_done", count=i + 1)  # llm_done, not tts.end: a superseded reply also ends its audio
        assert call.ws.of("llm_done")[0]["text"] == safety_gate.crisis_reply()
        sent = [c for c in llm.cues]  # one entry per LLM-built prompt: turns 1-3 are inside the cooldown, turn 4 is not
        assert len(sent) == 4 and all(c == "" for c in sent[:3])
        assert sent[-1] == CUE


@pytest.mark.asyncio
async def test_support_level_alerts_but_the_language_model_still_answers_without_a_cue():
    async with Call(["unused"]) as call:
        llm = CueLlm()
        with_emotion(call, FakeEmotion(result()), llm)
        await opt_in(call)
        call.ws.put_json({"type": "text_message", "turn_id": "t1", "text": "I feel hopeless lately."})
        await call.until("tts.end")
        assert call.ws.of("safety.alert")[0]["level"] == "support_suggested"
        assert llm.prompts and call.ws.of("llm_done")[0]["text"] != safety_gate.crisis_reply()
        assert all(c == "" for c in llm.cues)


@pytest.mark.asyncio
async def test_the_users_words_are_not_in_the_log(caplog):
    caplog.set_level(logging.DEBUG)
    async with Call(["I keep thinking about my secret plan to quit."]) as call:
        await call.speak()
        await call.until("tts.end")
        call.ws.put_json({"type": "text_message", "turn_id": "t9", "text": "my private sentence about purple elephants"})
        await call.until("tts.end", count=2)
    log = caplog.text
    assert "secret plan" not in log and "purple elephants" not in log
    assert "words" in log  # sizes are logged instead


def test_bangladesh_is_the_default_and_names_verified_local_resources():
    text = safety_gate.crisis_reply()
    assert "999" in text and "09612-119911" in text and "Kaan Pete Roi" in text
    spoken = safety_gate.crisis_reply("bd", spoken=True)
    assert not any(ch.isdigit() for ch in spoken)  # the voice must not read numbers as one big number


def test_unknown_country_gets_a_generic_text_without_invented_numbers():
    text = safety_gate.crisis_reply("ZZ")
    assert "local emergency number" in text and not any(ch.isdigit() for ch in text)


@pytest.mark.asyncio
async def test_the_apps_country_choice_selects_the_resources():
    async with Call(["unused"]) as call:
        call.ws.put_json({"type": "session.configure", "country": "zz"})
        await call.until("session.ready")
        call.ws.put_json({"type": "text_message", "turn_id": "t1", "text": "I want to die."})
        await call.until("llm_done")
        assert call.ws.of("llm_done")[0]["text"] == safety_gate.crisis_reply("ZZ")
