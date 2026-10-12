"""Tests for the optional emotion cue in `session.Session` (fake models, fake socket, fake emotion service: no GPU, no network).

What must hold: off by default and without the app's opt-in; with it, the hedged cue reaches the chat model's prompt, the app is told
what was inferred, self-harm language raises a safety flag instead of a cue, and a slow, broken or absent emotion service never stops
or delays a reply beyond its own timeout.  Run: python -m pytest test_emotion_session.py
"""
import asyncio
from typing import Any, Dict, List, Optional

import pytest

from emotion_client import EmotionClient
from llm_service import EMOTION_CUE_MAX_CHARS, LlmService
from test_session_logic import Call, FakeLlm, silence_frame, speech_frame

CUE = "(Private note, never mention it: their voice and words may suggest they feel low or tired. This is a weak guess, not a fact.)"


def result(cue: Optional[str] = CUE, safety: Optional[str] = None, mood: str = "low or tired") -> Dict[str, Any]:
    return {"model_version": "test",
            "estimate": {"lv": {"negative": 0.8, "neutral": 0.1, "positive": 0.1}, "la": {"low": 0.7, "mid": 0.2, "high": 0.1}, "l7": {"sad": 0.6}},
            "decision": {"pattern": "AT", "mood": mood, "tier": "clear", "valence": -0.7, "arousal": -0.6, "suppressed": None if cue else "x", "safety": safety},
            "cue": cue}


class FakeEmotion:
    enabled = True

    def __init__(self, res: Optional[Dict[str, Any]] = None, usable: bool = True, delay: float = 0.0,
                 audio_delay: float = 0.0, accept_audio: bool = True) -> None:
        self.res, self._usable, self.delay = res, usable, delay
        self.audio_delay, self.accept_audio = audio_delay, accept_audio
        self.order: List[str] = []
        self.audio: List[Dict[str, Any]] = []
        self.finalized: List[Dict[str, Any]] = []
        self.texts: List[str] = []
        self.resets: List[str] = []

    @property
    def usable(self) -> bool:
        return self._usable

    async def start_audio(self, session_id, turn_id, pcm, sample_rate):
        if self.audio_delay:
            await asyncio.sleep(self.audio_delay)  # a slow upload
        self.audio.append({"turn_id": turn_id, "bytes": len(pcm), "sr": sample_rate})
        self.order.append("audio_done")
        return self.accept_audio

    async def finalize(self, session_id, turn_id, text, use_audio=True):
        self.order.append("finalize")
        self.finalized.append({"turn_id": turn_id, "text": text, "use_audio": use_audio})
        if self.delay:
            await asyncio.sleep(self.delay)
        return self.res

    async def text(self, session_id, text):
        self.texts.append(text)
        return self.res

    async def reset(self, session_id):
        self.resets.append(session_id)


class CueLlm(FakeLlm):
    """FakeLlm that accepts and records the emotion cue (the real LlmService does)."""

    def build_messages(self, user_message, history=None, memory=None, summary="", spoken=False, emotion_cue=""):
        self.cues = getattr(self, "cues", []) + [emotion_cue]
        return super().build_messages(user_message, history, memory, summary, spoken)


def with_emotion(call: Call, fake: FakeEmotion, llm: Optional[CueLlm] = None) -> FakeEmotion:
    call.session.emotion = fake
    if llm is not None:
        call.session.llm = call.llm = llm
    return fake


async def opt_in(call: Call) -> None:
    call.ws.put_json({"type": "session.configure", "emotion": {"enabled": True}})
    await call.until("session.ready")


@pytest.mark.asyncio
async def test_off_by_default_and_without_the_apps_opt_in():
    async with Call(["I am tired."]) as call:
        fake = with_emotion(call, FakeEmotion(result()))  # server side enabled, but the app never opted in
        await call.speak()
        await call.until("tts.end")
        assert fake.audio == [] and fake.finalized == [] and "emotion.update" not in call.ws.types()
        assert call.llm.prompts  # the reply still worked (FakeLlm has no emotion_cue parameter: it would raise if one were passed)


@pytest.mark.asyncio
async def test_session_ready_reports_emotion_only_when_asked():
    async with Call(["x"]) as call:
        with_emotion(call, FakeEmotion(result()))
        call.ws.put_json({"type": "session.configure", "mode": "duplex_call"})
        ready = await call.until("session.ready")
        assert "emotion" not in ready
        call.ws.put_json({"type": "session.configure", "emotion": {"enabled": True}})
        await call.until("session.ready", count=2)
        assert call.ws.of("session.ready")[-1]["emotion"] == {"enabled": True, "server_enabled": True}


@pytest.mark.asyncio
async def test_cue_reaches_the_prompt_and_the_app_is_told():
    async with Call(["I have been feeling really low lately."]) as call:
        fake = with_emotion(call, FakeEmotion(result()), CueLlm())
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        assert fake.audio and fake.audio[0]["sr"] == 16000 and fake.audio[0]["bytes"] > 16000  # the turn's audio was handed over
        assert fake.finalized[0]["text"] == "I have been feeling really low lately."
        assert call.llm.cues[-1] == CUE
        update = call.ws.of("emotion.update")[0]
        assert update["mood"] == "low or tired" and update["cue_used"] is True and update["source"] == "voice"
        assert update["estimate"]["lv"]["negative"] == 0.8
        order = call.ws.types()
        assert order.index("transcript_final") < order.index("emotion.update") < order.index("llm_start")
        assert "safety.alert" not in order


@pytest.mark.asyncio
async def test_the_result_is_only_requested_after_the_audio_upload_finished():
    async with Call(["I have been feeling really low lately."]) as call:
        fake = with_emotion(call, FakeEmotion(result(), audio_delay=0.4), CueLlm())  # the upload is slower than the STT
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        assert fake.order == ["audio_done", "finalize"]  # never the other way round (that was a real race)
        assert fake.finalized[0]["use_audio"] is True


@pytest.mark.asyncio
async def test_text_only_when_the_service_did_not_accept_the_audio():
    async with Call(["I have been feeling really low lately."]) as call:
        fake = with_emotion(call, FakeEmotion(result(), accept_audio=False), CueLlm())  # e.g. the turn was too short for the service
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        assert fake.finalized[0]["use_audio"] is False and call.llm.cues[-1] == CUE


@pytest.mark.asyncio
async def test_no_cue_when_the_service_has_none():
    async with Call(["The meeting is at three."]) as call:
        with_emotion(call, FakeEmotion(result(cue=None, mood=None)), CueLlm())
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        assert call.llm.cues == [] or call.llm.cues[-1] == ""  # the keyword is only passed when there is a cue
        assert call.ws.of("emotion.update")[0]["cue_used"] is False


@pytest.mark.asyncio
async def test_a_dead_service_never_breaks_the_reply():
    async with Call(["Hello there."]) as call:
        fake = with_emotion(call, FakeEmotion(None), CueLlm())  # every call returns None, like a down or timed-out service
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        assert fake.finalized and "emotion.update" not in call.ws.types()
        assert call.ws.of("tts.end")[0]["cancelled"] is False


@pytest.mark.asyncio
async def test_self_harm_language_raises_a_flag_and_no_cue():
    async with Call(["I will kill myself."]) as call:
        with_emotion(call, FakeEmotion(result(cue=None, safety="self_harm_language")), CueLlm())
        await opt_in(call)
        await call.speak()
        await call.until("tts.end")
        alert = call.ws.of("safety.alert")[0]
        assert alert["level"] == "urgent_support"
        assert call.ws.of("emotion.update")[0]["cue_used"] is False
        assert "kill" not in str(call.ws.of("safety.alert"))  # the alert carries a level, never the user's words


@pytest.mark.asyncio
async def test_text_chat_uses_the_text_endpoint():
    async with Call(["unused"]) as call:
        fake = with_emotion(call, FakeEmotion(result()), CueLlm())
        await opt_in(call)
        call.ws.put_json({"type": "text_message", "turn_id": "t1", "text": "I feel so alone."})
        await call.until("tts.end")
        assert fake.texts == ["I feel so alone."] and fake.audio == []
        assert call.llm.cues[-1] == CUE
        assert call.ws.of("emotion.update")[0]["source"] == "text"


@pytest.mark.asyncio
async def test_shutdown_resets_the_sessions_emotion_state():
    call = Call(["hi"])
    async with call:
        fake = with_emotion(call, FakeEmotion(result()))
        await opt_in(call)
    await asyncio.sleep(0.05)
    assert fake.resets == ["sess_test"]


def test_real_llm_prompt_gets_the_cue_flattened_and_capped():
    llm = LlmService()
    plain = llm.build_messages("hi")[0]["content"]
    assert "Private note" not in plain
    messy = "(Private note\n\n  with   odd\tspacing) " + "x" * 2000
    system = llm.build_messages("hi", emotion_cue=messy)[0]["content"]
    assert system.startswith(plain)
    added = system[len(plain):]
    assert added.startswith("\n") and "\n" not in added[1:] and len(added) <= 1 + EMOTION_CUE_MAX_CHARS
    assert llm.build_messages("hi", emotion_cue="")[0]["content"] == plain


@pytest.mark.asyncio
async def test_client_is_off_without_the_flag_and_breaks_the_circuit_when_the_service_is_down():
    assert EmotionClient(enabled=False).usable is False
    c = EmotionClient(base_url="http://127.0.0.1:9", timeout_s=0.2, enabled=True)  # nothing listens on port 9
    assert await c.finalize("s", "t", "hello") is None
    assert await c.finalize("s", "t", "hello") is None
    assert c.usable is False  # two failures open the breaker: further calls cost nothing for a while
    assert await c.text("s", "hello") is None
    await c.aclose()


@pytest.mark.asyncio
async def test_a_turn_that_overlaps_the_assistants_voice_is_not_analysed_for_emotion():
    async with Call(["First thing.", "Second thing."], tts_ms=2000, barge_in=True) as call:
        fake = with_emotion(call, FakeEmotion(result()), CueLlm())
        await opt_in(call)
        await call.speak()
        await call.until("turn.latency")
        assert len(fake.audio) == 1  # the first turn was the person alone: analysed
        await call.stream(speech_frame(), 800)  # cuts in while Sol is audible
        await call.stream(silence_frame(), 1100)
        await call.until("transcript_final", count=2)
        await call.until("llm_start", count=2)
        assert len(fake.audio) == 1  # her voice may be in the second turn: no audio handed over
        assert fake.finalized[-1]["use_audio"] is False  # words only
