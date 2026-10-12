"""Tests for the journal check-in endpoints (fake speech-to-text and emotion service: no GPU, no network).

What must hold: the transcript and the emotion come back for text and voice; crisis language is reported as a level only; with the emotion
service off the entry still gets its transcript and an honest null analysis; camera frames are only used with the server switch AND the
app's face flag; recordings that are empty or too long are refused; and the emotion service's per-recording state is released after.
Run: python -m pytest test_journal_api.py
"""
from typing import Any, Dict, Optional

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import journal_api
from journal_api import build_router

PCM_2S = b"\x01\x00" * 32000  # 2 s of 16 kHz int16


class FakeStt:
    def __init__(self, text: str = "I had a long day and I feel tired.") -> None:
        self.text, self.calls = text, 0

    def transcribe(self, pcm: bytes, sample_rate: int = 16000):
        self.calls += 1
        return self.text, 0.9, "en"


def estimate(mood: Optional[str] = "low or tired", pattern: str = "AT") -> Dict[str, Any]:
    return {"model_version": "test", "estimate": {"l7": {"sad": 0.5}, "lv": {"negative": 0.7, "neutral": 0.2, "positive": 0.1},
                                                  "la": {"low": 0.6, "mid": 0.3, "high": 0.1}},
            "decision": {"pattern": pattern, "mood": mood, "tier": "clear", "valence": -0.6, "arousal": -0.5, "suppressed": None,
                         "safety": None},
            "cue": "SHOULD NOT LEAK"}


class FakeEmotion:
    def __init__(self, usable: bool = True) -> None:
        self.usable = usable
        self.audio, self.finalized, self.texts, self.frames, self.resets = [], [], [], [], []

    async def start_audio(self, session_id, turn_id, pcm, sample_rate, chunk_s=0.0):
        self.audio.append((turn_id, len(pcm)))
        return True

    async def finalize(self, session_id, turn_id, text, use_audio=True, max_audio_wait_ms=500, face_window=None, timeout_s=None):
        self.finalized.append({"text": text, "use_audio": use_audio, "face_window": face_window})
        return estimate(pattern="ATV" if face_window else "AT")

    async def text(self, session_id, text):
        self.texts.append(text)
        return estimate(pattern="T")

    async def frame(self, session_id, t, jpeg):
        self.frames.append(len(jpeg))
        return {"accepted": True, "usable": 1}

    async def reset(self, session_id):
        self.resets.append(session_id)


def client(stt=None, emotion=None) -> TestClient:
    app = FastAPI()
    app.include_router(build_router(stt or FakeStt(), emotion or FakeEmotion()))
    return TestClient(app)


def test_text_entry_returns_the_words_and_a_real_estimate_without_the_chat_cue():
    emo = FakeEmotion()
    r = client(emotion=emo).post("/v1/journal/text", json={"session_id": "j1", "text": "I feel so alone lately."})
    body = r.json()
    assert r.status_code == 200 and body["transcript"] == "I feel so alone lately."
    assert body["emotion"]["mood"] == "low or tired" and body["emotion"]["pattern"] == "T"
    assert "cue" not in body["emotion"] and "SHOULD NOT LEAK" not in r.text
    assert emo.resets == ["j1"]  # nothing is kept for this entry


def test_voice_entry_is_transcribed_and_analysed_from_audio_and_words():
    stt, emo = FakeStt(), FakeEmotion()
    r = client(stt, emo).post("/v1/journal/audio?session_id=j2&sample_rate=16000", content=PCM_2S)
    body = r.json()
    assert r.status_code == 200 and body["transcript"] == "I had a long day and I feel tired."
    assert body["duration_s"] == 2.0 and body["emotion"]["pattern"] == "AT"
    assert emo.audio and emo.finalized[0]["use_audio"] is True and emo.finalized[0]["face_window"] is None
    assert stt.calls == 1 and emo.resets == ["j2"]


def test_the_emotion_service_being_off_still_gives_the_transcript_and_an_honest_null():
    r = client(emotion=FakeEmotion(usable=False)).post("/v1/journal/audio?session_id=j3", content=PCM_2S)
    body = r.json()
    assert r.status_code == 200 and body["transcript"] and body["emotion"] is None


def test_crisis_language_is_reported_as_a_level():
    r = client(FakeStt("I want to die"), FakeEmotion()).post("/v1/journal/audio?session_id=j4", content=PCM_2S)
    assert r.json()["safety"] == "urgent_support"
    t = client().post("/v1/journal/text", json={"session_id": "j5", "text": "just a normal day"})
    assert t.json()["safety"] is None


def test_frames_are_ignored_without_the_server_switch(monkeypatch):
    monkeypatch.setattr(journal_api, "FACE_SERVER_ENABLED", False)
    emo = FakeEmotion()
    c = client(emotion=emo)
    assert c.post("/v1/journal/frame?session_id=j6", content=b"x" * 500).json() == {"usable": None, "accepted": False}
    c.post("/v1/journal/audio?session_id=j6&face=1", content=PCM_2S)
    assert emo.frames == [] and emo.finalized[0]["face_window"] is None


def test_with_the_switch_and_the_apps_face_flag_the_recordings_frames_join_the_estimate(monkeypatch):
    monkeypatch.setattr(journal_api, "FACE_SERVER_ENABLED", True)
    emo = FakeEmotion()
    c = client(emotion=emo)
    assert c.post("/v1/journal/frame?session_id=j7", content=b"x" * 500).json() == {"usable": 1, "accepted": True}
    body = c.post("/v1/journal/audio?session_id=j7&face=1", content=PCM_2S).json()
    assert body["emotion"]["pattern"] == "ATV"
    w = emo.finalized[0]["face_window"]
    assert w and w[0] < w[1]

    # No face flag from the app (no camera consent): the frames are NOT used even though they were uploaded.
    c.post("/v1/journal/frame?session_id=j8", content=b"x" * 500)
    c.post("/v1/journal/audio?session_id=j8&face=0", content=PCM_2S)
    assert emo.finalized[1]["face_window"] is None


@pytest.mark.parametrize("path,payload,code", [
    ("/v1/journal/audio?session_id=a", b"", 400),
    ("/v1/journal/audio?session_id=a", b"\x01\x00" * 100, 400),
    ("/v1/journal/audio?session_id=a&sample_rate=100", PCM_2S, 400),
    ("/v1/journal/audio?session_id=a", b"\x01\x00" * (16000 * 181), 413),
], ids=["empty", "too_short", "bad_rate", "too_long"])
def test_bad_recordings_are_refused(path, payload, code):
    assert client().post(path, content=payload).status_code == code


def test_empty_text_is_refused():
    assert client().post("/v1/journal/text", json={"session_id": "x", "text": "   "}).status_code == 400
