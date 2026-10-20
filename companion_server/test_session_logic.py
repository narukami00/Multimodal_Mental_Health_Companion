"""Behavioural tests for `session.Session` with fake models and a fake socket.

No GPU, no models, no server: the VAD sees loud sine = speech and zeros = silence,
the STT returns scripted text, the LLM yields scripted chunks and the TTS returns
silent PCM of a fixed length. What is under test is the turn-taking, the reply
pipeline and the history rules - the parts that decide whether a call feels
seamless.
"""

import asyncio
import json
import math
import struct
import time
from typing import Any, Dict, List, Optional

import numpy as np
import pytest

import session as session_module
from session import Session, looks_incomplete
from stt_service import StreamingVad
from tts_engine import TtsAudioResult

FRAME_SAMPLES = 320  # 20 ms @ 16 kHz
FRAME_BYTES = FRAME_SAMPLES * 2
STREAM_ID = 1001


# --------------------------------------------------------------------- fakes


class _Prob:
    def __init__(self, value: float) -> None:
        self._value = value

    def item(self) -> float:
        return self._value


class EnergyVadModel:
    """Silero stand-in: a loud window is speech, a quiet one is not."""

    def __call__(self, window, sample_rate):
        rms = float(window.abs().mean()) * 32768.0
        return _Prob(0.95 if rms > 1000 else 0.02)

    def reset_states(self) -> None:
        pass


class FakeStt:
    vad_threshold = 0.5
    vad_neg_threshold = 0.35
    vad_min_speech_ms = 120
    is_ready = True
    device = "fake"

    def __init__(self, transcripts: List[str], delay: float = 0.0) -> None:
        self.transcripts = list(transcripts)
        self.delay = delay
        self.transcribed: List[int] = []

    def new_streaming_vad(self, sample_rate: int = 16000, keep_history: bool = True):
        return StreamingVad(EnergyVadModel(), sample_rate=sample_rate, keep_history=keep_history)

    def transcribe_pcm(self, pcm: bytes, sample_rate: int = 16000, speech_ms: int = 0):
        self.transcribed.append(len(pcm))
        if self.delay:
            time.sleep(self.delay)  # runs on a worker thread, like the real model
        text = self.transcripts.pop(0) if self.transcripts else "Okay."
        return text, 0.9, "en"


class FakeLlm:
    model_id = "fake-llm"
    is_ready = True

    def __init__(self, replies: Optional[List[str]] = None, token_delay: float = 0.0) -> None:
        self.replies = list(replies or ["I hear you. That sounds heavy. I am right here."])
        self.token_delay = token_delay
        self.prompts: List[List[Dict[str, str]]] = []

    def build_messages(self, user_message, history=None, memory=None, summary="", spoken=False):
        messages = [{"role": "system", "content": "sys"}]
        messages.extend(history or [])
        messages.append({"role": "user", "content": user_message})
        self.prompts.append(messages)
        return messages

    async def generate_stream_async(self, messages, max_new_tokens=128, temperature=0.7,
                                    top_p=0.9, cancel=None):
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        for word in reply.split(" "):
            if cancel is not None and cancel.is_set():
                return
            await asyncio.sleep(self.token_delay)
            yield word + " "

    @staticmethod
    def fallback_suggestions(assistant_text, user_text=""):
        return ["Tell me more", "That resonates", "What next?"]

    async def extract_moment_async(self, text):
        return None

    async def summarize_async(self, previous, turns):
        return {"summary": "s", "method": "extractive"}


class FakeTts:
    name = "fake"
    is_ready = True
    default_sample_rate = 24000

    def __init__(self, ms_per_clause: int = 1000) -> None:
        self.ms_per_clause = ms_per_clause

    def synthesize(self, text, voice_id=None, speed=0.96):
        samples = self.default_sample_rate * self.ms_per_clause // 1000
        pcm = bytes(samples * 2)
        return TtsAudioResult(pcm_bytes=pcm, sample_rate=self.default_sample_rate,
                              duration_sec=self.ms_per_clause / 1000, samples=np.zeros(1))

    def warmup(self):
        pass

    def get_available_voices(self):
        return []


class FakeWebSocket:
    def __init__(self) -> None:
        self.inbox: "asyncio.Queue[Dict[str, Any]]" = asyncio.Queue()
        self.events: List[Dict[str, Any]] = []
        self.binary: List[bytes] = []
        self.accepted = False

    async def accept(self):
        self.accepted = True

    async def receive(self):
        return await self.inbox.get()

    async def send_text(self, text: str):
        event = json.loads(text)
        event["_at"] = time.monotonic()
        self.events.append(event)

    async def send_bytes(self, data: bytes):
        self.binary.append(data)

    # -- test helpers
    def put_json(self, payload: Dict[str, Any]) -> None:
        self.inbox.put_nowait({"type": "websocket.receive", "text": json.dumps(payload)})

    def put_frame(self, seq: int, pcm: bytes) -> None:
        self.inbox.put_nowait({"type": "websocket.receive",
                               "bytes": struct.pack("<II", STREAM_ID, seq) + pcm})

    def types(self) -> List[str]:
        return [e["type"] for e in self.events]

    def of(self, event_type: str) -> List[Dict[str, Any]]:
        return [e for e in self.events if e["type"] == event_type]


def speech_frame() -> bytes:
    t = np.arange(FRAME_SAMPLES)
    return (9000 * np.sin(2 * math.pi * 220 * t / 16000)).astype(np.int16).tobytes()


def silence_frame() -> bytes:
    return bytes(FRAME_BYTES)


class Call:
    """A running session plus the client-side helpers a test needs."""

    def __init__(self, transcripts, replies=None, tts_ms=1000, barge_in=False,
                 vad: Optional[Dict[str, Any]] = None, token_delay: float = 0.0,
                 stt_delay: float = 0.0) -> None:
        self.ws = FakeWebSocket()
        self.stt = FakeStt(transcripts, delay=stt_delay)
        self.llm = FakeLlm(replies, token_delay=token_delay)
        self.tts = FakeTts(tts_ms)
        self.session = Session(self.ws, self.stt, self.llm, self.tts, session_id="sess_test")
        self.barge_in = barge_in
        self.vad = vad
        self.seq = 0
        self._runner: Optional[asyncio.Task] = None

    async def __aenter__(self) -> "Call":
        self._runner = asyncio.create_task(self.session.run())
        if self.vad:
            self.ws.put_json({"type": "session.configure", "mode": "duplex_call", "vad": self.vad})
        self.ws.put_json({"type": "call.listen", "sample_rate": 16000, "barge_in": self.barge_in})
        await self.until("call.listening")
        return self

    async def __aexit__(self, *exc) -> None:
        self.ws.inbox.put_nowait({"type": "websocket.disconnect", "code": 1000})
        await asyncio.wait_for(self._runner, 5)

    async def stream(self, frame: bytes, ms: int) -> None:
        for _ in range(ms // 20):
            self.ws.put_frame(self.seq, frame)
            self.seq += 1
        await asyncio.sleep(0)

    async def speak(self, ms: int = 1200, then_silence_ms: int = 1100) -> None:
        await self.stream(speech_frame(), ms)
        await self.stream(silence_frame(), then_silence_ms)

    async def until(self, event_type: str, timeout: float = 5.0, count: int = 1) -> Dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            matches = self.ws.of(event_type)
            if len(matches) >= count:
                return matches[count - 1]
            await asyncio.sleep(0.01)
        raise AssertionError(f"no {event_type!r} within {timeout}s; saw {self.ws.types()}")

    async def until_cancelled_tts_end(self, timeout: float = 5.0) -> Dict[str, Any]:
        """The audio went out in full (`tts.end` complete); wait for the cancel notice."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for event in self.ws.of("tts.end"):
                if event["cancelled"]:
                    return event
            await asyncio.sleep(0.01)
        raise AssertionError(f"no cancelled tts.end; saw {self.ws.types()}")

    async def settle(self, seconds: float = 0.3) -> None:
        await asyncio.sleep(seconds)


# ------------------------------------------------------------------- the tests


@pytest.mark.asyncio
async def test_room_noise_never_opens_a_turn():
    async with Call(["never used"]) as call:
        await call.stream(silence_frame(), 4000)
        await call.settle()
        assert "turn.started" not in call.ws.types()
        assert call.stt.transcribed == []


@pytest.mark.asyncio
async def test_a_spoken_turn_is_heard_endpointed_and_answered_in_order():
    async with Call(["I am not feeling okay."]) as call:
        await call.speak()
        await call.until("tts.end")
        order = call.ws.types()
        for earlier, later in [
            ("turn.started", "turn.speech_detected"),
            ("turn.speech_detected", "turn.endpointed"),
            ("turn.endpointed", "transcript_final"),
            ("transcript_final", "llm_start"),
            ("llm_start", "tts.start"),
            ("tts.start", "tts.segment"),
            ("llm_done", "tts.end"),
        ]:
            assert order.index(earlier) < order.index(later), f"{earlier} before {later}: {order}"
        endpointed = call.ws.of("turn.endpointed")[0]
        assert endpointed["reason"] == "silence"
        assert call.ws.of("transcript_final")[0]["text"] == "I am not feeling okay."
        assert call.ws.of("tts.end")[0]["cancelled"] is False
        assert call.session.history[0] == {"role": "user", "content": "I am not feeling okay."}
        # Phases walk the whole cycle: listening, thinking, speaking.
        phases = [e["state"] for e in call.ws.of("call.state")]
        assert phases[:4] == ["idle", "user_speaking", "thinking", "assistant_speaking"]


@pytest.mark.asyncio
async def test_the_reply_reports_where_its_time_went():
    async with Call(["Hello there."]) as call:
        await call.speak()
        report = await call.until("turn.latency")
        assert report["to_first_audio_ms"] >= 0
        assert report["stt_ms"] is not None


@pytest.mark.asyncio
async def test_a_cough_is_discarded_not_answered():
    async with Call(["never used"]) as call:
        await call.stream(speech_frame(), 160)  # 160 ms: confirmed, but too short
        await call.stream(silence_frame(), 1000)
        discarded = await call.until("turn.discarded")
        assert discarded["reason"] == "too_short"
        assert call.stt.transcribed == []
        assert "llm_start" not in call.ws.types()


@pytest.mark.asyncio
async def test_unintelligible_speech_hands_the_floor_back():
    async with Call([""]) as call:
        await call.speak()
        failed = await call.until("transcript_failed")
        assert failed["reason"] == "unintelligible"
        await call.until("turn.discarded")
        await call.settle()
        assert call.session.phase.value == "idle"
        assert "llm_start" not in call.ws.types()


@pytest.mark.asyncio
async def test_speech_while_the_assistant_is_audible_is_ignored_without_barge_in():
    """A speakerphone's own echo must never become a turn."""
    async with Call(["First thing.", "never"], tts_ms=2000, barge_in=False) as call:
        await call.speak()
        await call.until("turn.latency")  # first audio is out; ~6 s of it is queued
        before = len(call.ws.of("turn.started"))
        await call.speak(ms=800, then_silence_ms=900)
        await call.settle()
        assert len(call.ws.of("turn.started")) == before
        assert not call.ws.of("tts.end") or call.ws.of("tts.end")[0]["cancelled"] is False


@pytest.mark.asyncio
async def test_speaking_over_the_assistant_interrupts_it_when_barge_in_is_on():
    async with Call(["First thing.", "Second thing."], tts_ms=2000, barge_in=True) as call:
        await call.speak()
        await call.until("turn.latency")
        await call.stream(speech_frame(), 800)
        cancelled = await call.until_cancelled_tts_end()
        assert cancelled["reason"] == "user_speech"
        interrupted = await call.until("turn.interrupted")
        assert interrupted["source"] == "server_vad"
        assert len(call.ws.of("turn.started")) == 2  # the interruption is itself a turn


@pytest.mark.asyncio
async def test_an_interruption_before_anything_was_heard_merges_into_the_next_turn():
    async with Call(["I have had a rough day", "and I cannot sleep."],
                    replies=["Reply one. More words here. And more."], tts_ms=2000,
                    barge_in=True) as call:
        await call.speak()
        await call.until("turn.latency")
        await call.stream(speech_frame(), 900)   # cuts in before any clause was heard
        await call.stream(silence_frame(), 1100)
        await call.until("transcript_final", count=2)
        await call.until("llm_start", count=2)
        # The assistant never got to say anything, so the person's two halves are
        # one turn and the model sees them together.
        last_prompt = call.llm.prompts[-1]
        assert last_prompt[-1]["content"] == "I have had a rough day and I cannot sleep."
        assert [m for m in last_prompt if m["role"] == "assistant"] == []


@pytest.mark.asyncio
async def test_an_interruption_mid_reply_records_only_what_was_heard():
    async with Call(["Tell me a story."], tts_ms=1000, barge_in=False) as call:
        await call.speak()
        await call.until("tts.end")
        assert call.session.history[1]["content"].startswith("I hear you.")
        # The phone reports the interruption 1.4 s in: one clause fully heard.
        call.ws.put_json({"type": "turn.interrupted", "turn_id": "x", "played_ms": 1400})
        await call.settle()
        assert call.session.history[1]["content"] == "I hear you."


@pytest.mark.asyncio
async def test_an_unfinished_sentence_waits_for_its_continuation():
    transcripts = ["I just feel like, and", "everything is too much."]
    async with Call(transcripts, vad={"carry_hold_ms": 5000}) as call:
        await call.speak()
        await call.until("transcript_final")
        await call.settle(0.3)
        assert "llm_start" not in call.ws.types()  # held, not answered
        await call.speak()
        await call.until("llm_start")
        assert call.llm.prompts[-1][-1]["content"] == "I just feel like, and everything is too much."


@pytest.mark.asyncio
async def test_an_unfinished_sentence_is_answered_when_nothing_follows():
    async with Call(["I just feel like, and"], vad={"carry_hold_ms": 200}) as call:
        await call.speak()
        await call.until("llm_start", timeout=3.0)
        assert call.llm.prompts[-1][-1]["content"] == "I just feel like, and"


@pytest.mark.asyncio
async def test_muting_drops_the_open_turn_and_ignores_audio():
    async with Call(["never"]) as call:
        await call.stream(speech_frame(), 600)
        await call.until("turn.started")
        call.ws.put_json({"type": "call.mute", "muted": True})
        discarded = await call.until("turn.discarded")
        assert discarded["reason"] == "cancelled"
        await call.speak()
        await call.settle()
        assert call.stt.transcribed == []
        assert len(call.ws.of("turn.started")) == 1


@pytest.mark.asyncio
async def test_audio_after_unmute_opens_turns_again():
    async with Call(["Back again."]) as call:
        call.ws.put_json({"type": "call.mute", "muted": True})
        await call.stream(speech_frame(), 400)
        call.ws.put_json({"type": "call.mute", "muted": False})
        await call.speak()
        await call.until("transcript_final")
        assert call.ws.of("transcript_final")[0]["text"] == "Back again."


@pytest.mark.asyncio
async def test_a_turn_still_being_transcribed_does_not_answer_into_a_finished_call():
    async with Call(["Too late."], stt_delay=0.4) as call:
        await call.speak()
        await call.until("turn.endpointed")
        call.ws.put_json({"type": "call.end", "reason": "user_ended_call"})
        await call.settle(0.9)
        assert "llm_start" not in call.ws.types()
        assert "transcript_final" not in call.ws.types()


@pytest.mark.asyncio
async def test_starting_a_new_call_silences_the_last_one():
    async with Call(["First call."], tts_ms=2000) as call:
        await call.speak()
        await call.until("turn.latency")  # the reply is audible
        call.ws.put_json({"type": "call.listen", "sample_rate": 16000})
        cancelled = await call.until_cancelled_tts_end()
        assert cancelled["reason"] == "new_call"


@pytest.mark.asyncio
async def test_a_dropped_capture_frame_is_reported():
    async with Call(["never"]) as call:
        await call.stream(silence_frame(), 100)
        call.seq += 2  # two frames never arrive
        await call.stream(silence_frame(), 60)
        gap = await call.until("turn.diagnostic")
        assert gap["reason"] == "frame_gap" and gap["missing"] == 2


@pytest.mark.asyncio
async def test_a_second_turn_does_not_leak_into_the_first_reply():
    async with Call(["First question.", "Second question."], tts_ms=100) as call:
        await call.speak()
        await call.until("tts.end")
        await asyncio.sleep(1.5)  # let the first reply's audio window pass
        await call.speak()
        await call.until("tts.end", count=2)
        assert [m["content"] for m in call.session.history if m["role"] == "user"] == [
            "First question.", "Second question.",
        ]


@pytest.mark.asyncio
async def test_text_chat_streams_text_and_voice_and_keeps_history():
    ws = FakeWebSocket()
    llm, tts = FakeLlm(["Hello friend. Welcome back."]), FakeTts(300)
    sess = Session(ws, FakeStt([]), llm, tts, session_id="sess_chat")
    runner = asyncio.create_task(sess.run())
    ws.put_json({"type": "text_message", "turn_id": "t1", "text": "Hi there"})
    deadline = time.monotonic() + 5
    while "tts.end" not in ws.types() and time.monotonic() < deadline:
        await asyncio.sleep(0.01)
    done = ws.of("llm_done")[0]
    assert done["text"] == "Hello friend. Welcome back."
    assert done["suggestions"] == ["Tell me more", "That resonates", "What next?"]
    assert "echo" in ws.types()
    assert sess.history == [
        {"role": "user", "content": "Hi there"},
        {"role": "assistant", "content": "Hello friend. Welcome back."},
    ]
    ws.put_json({"type": "text_message", "turn_id": "t2", "text": "And again"})
    while len(ws.of("llm_start")) < 2 and time.monotonic() < deadline:
        await asyncio.sleep(0.01)
    assert ws.of("llm_start")[1]["history_messages"] == 2
    ws.inbox.put_nowait({"type": "websocket.disconnect", "code": 1000})
    await asyncio.wait_for(runner, 5)


@pytest.mark.asyncio
async def test_stopping_the_voice_keeps_the_text_coming():
    ws = FakeWebSocket()
    llm, tts = FakeLlm(["One. Two. Three. Four."], token_delay=0.05), FakeTts(300)
    sess = Session(ws, FakeStt([]), llm, tts, session_id="sess_stop")
    runner = asyncio.create_task(sess.run())
    ws.put_json({"type": "text_message", "turn_id": "t1", "text": "Count"})
    deadline = time.monotonic() + 5
    while "tts.start" not in ws.types() and time.monotonic() < deadline:
        await asyncio.sleep(0.01)
    ws.put_json({"type": "speech.cancel", "cancel_tts": True, "cancel_llm": False})
    while "llm_done" not in ws.types() and time.monotonic() < deadline:
        await asyncio.sleep(0.01)
    ended = ws.of("tts.end")
    assert ended and ended[0]["cancelled"] is True
    assert ws.of("llm_done")[0]["text"] == "One. Two. Three. Four."
    ws.inbox.put_nowait({"type": "websocket.disconnect", "code": 1000})
    await asyncio.wait_for(runner, 5)


# ------------------------------------------------------------ pure functions


@pytest.mark.parametrize("text, expected", [
    ("I am not feeling okay", False),          # no period, but nothing says unfinished
    ("I am not feeling okay.", False),
    ("Hey, how are you doing today?", False),
    ("It feels like I constantly have to carry a heavy weight on my back.", False),
    ("I just feel like,", True),                # trailing comma
    ("Well...", True),                          # trailing ellipsis
    ("I was thinking that", True),              # ends on a connector
    ("It is just that I have been so", True),
    ("", False),
])
def test_looks_incomplete(text, expected):
    assert looks_incomplete(text) is expected
