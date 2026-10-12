"""Tests for the camera-frame socket and the face consent in session.Session (fake service, no GPU, no network).

What must hold: no frame is ever analysed without the app's separate camera consent AND the server switch; consent is re-checked on every
frame; frames are dropped (not queued) when the service is busy; the camera frames of a turn's time window are handed to the emotion
estimate; the 'face' flag is only reported when the camera is really allowed.  Run: python -m pytest test_video_socket.py
"""
import asyncio
import struct
import time
from typing import Any, Dict

import pytest
from fastapi import FastAPI, WebSocket
from fastapi.testclient import TestClient

import session as session_module
from test_emotion_session import CueLlm, FakeEmotion, result, with_emotion
from test_session_logic import Call
from video_socket import serve_video

JPEG = b"\xff\xd8" + b"x" * 300 + b"\xff\xd9"


def frame(seq: int, body: bytes = JPEG) -> bytes:
    return struct.pack("<I", seq) + body


class FakeSession:
    def __init__(self, allowed: bool = True, delay: float = 0.0) -> None:
        self.allowed, self.delay, self.frames = allowed, delay, []

    def face_allowed(self) -> bool:
        return self.allowed

    async def video_frame(self, jpeg: bytes) -> Dict[str, Any]:
        if not self.allowed:
            return {"refused": "no_consent"}
        self.frames.append(len(jpeg))
        if self.delay:
            await asyncio.sleep(self.delay)
        return {"usable": 1}


def client_for(live: Dict[str, Any]) -> TestClient:
    app = FastAPI()

    @app.websocket("/ws/v1/video")
    async def route(websocket: WebSocket, session_id: str):
        await serve_video(websocket, session_id, live)

    return TestClient(app)


def test_unknown_session_is_refused():
    with client_for({}).websocket_connect("/ws/v1/video?session_id=nope") as ws:
        assert ws.receive_json() == {"type": "video.refused", "reason": "no_session"}


def test_no_camera_consent_means_nothing_is_analysed():
    fake = FakeSession(allowed=False)
    with client_for({"s1": fake}).websocket_connect("/ws/v1/video?session_id=s1") as ws:
        assert ws.receive_json() == {"type": "video.refused", "reason": "no_consent"}
    assert fake.frames == []


def test_frames_are_acknowledged_with_whether_a_face_was_usable():
    fake = FakeSession()
    with client_for({"s1": fake}).websocket_connect("/ws/v1/video?session_id=s1") as ws:
        ws.send_json({"type": "video.start", "codec": "jpeg", "upright": True})
        assert ws.receive_json() == {"type": "video.ready"}
        ws.send_bytes(frame(7))
        ack = ws.receive_json()
        assert ack["type"] == "video.ack" and ack["seq"] == 7 and ack["usable"] == 1
    assert fake.frames == [len(JPEG)]


def test_a_frame_before_start_is_refused_and_not_analysed():
    fake = FakeSession()
    with client_for({"s1": fake}).websocket_connect("/ws/v1/video?session_id=s1") as ws:
        ws.send_bytes(frame(1))
        assert ws.receive_json() == {"type": "video.refused", "reason": "bad_start"}
    assert fake.frames == []


def test_withdrawing_consent_mid_stream_stops_analysis_at_the_next_frame():
    fake = FakeSession()
    with client_for({"s1": fake}).websocket_connect("/ws/v1/video?session_id=s1") as ws:
        ws.send_json({"type": "video.start"})
        ws.receive_json()
        ws.send_bytes(frame(1))
        assert ws.receive_json()["type"] == "video.ack"
        fake.allowed = False  # the person turned the camera off in the app
        time.sleep(0.12)
        ws.send_bytes(frame(2))
        assert ws.receive_json() == {"type": "video.refused", "reason": "no_consent"}
    assert fake.frames == [len(JPEG)]  # only the first frame was ever analysed


def test_a_busy_service_drops_frames_instead_of_queueing_them():
    fake = FakeSession(delay=0.4)
    with client_for({"s1": fake}).websocket_connect("/ws/v1/video?session_id=s1") as ws:
        ws.send_json({"type": "video.start"})
        ws.receive_json()
        for n in range(1, 5):
            ws.send_bytes(frame(n))
            time.sleep(0.1)
        ack = ws.receive_json()
        assert ack["type"] == "video.ack" and ack["seq"] == 1
    assert len(fake.frames) == 1


def test_oversize_and_empty_frames_are_dropped_without_analysis():
    fake = FakeSession()
    with client_for({"s1": fake}).websocket_connect("/ws/v1/video?session_id=s1") as ws:
        ws.send_json({"type": "video.start"})
        ws.receive_json()
        ws.send_bytes(frame(1, b""))
        time.sleep(0.12)
        ws.send_bytes(frame(2, b"x" * 2_100_000))
        time.sleep(0.12)
        ws.send_bytes(frame(3))
        assert ws.receive_json()["seq"] == 3
    assert fake.frames == [len(JPEG)]


# ---- the session side ---------------------------------------------------------------------------------------------------

async def configure(call: Call, face: bool, opted_in: bool = True) -> Dict[str, Any]:
    call.ws.put_json({"type": "session.configure", "emotion": {"enabled": opted_in, "face_features": face}})
    return await call.until("session.ready")


@pytest.mark.asyncio
async def test_the_camera_needs_the_server_switch_the_emotion_opt_in_and_its_own_consent(monkeypatch):
    monkeypatch.setattr(session_module, "FACE_SERVER_ENABLED", True)
    async with Call(["x"]) as call:
        with_emotion(call, FakeEmotion(result()))
        ready = await configure(call, face=True)
        assert ready["emotion"]["face"] is True and call.session.face_allowed()
        assert await call.session.video_frame(JPEG) == {"usable": 1}

    async with Call(["x"]) as call:
        with_emotion(call, FakeEmotion(result()))
        await configure(call, face=False)  # voice and text consent only: the camera stays off
        assert not call.session.face_allowed()
        assert await call.session.video_frame(JPEG) == {"refused": "no_consent"}

    async with Call(["x"]) as call:
        with_emotion(call, FakeEmotion(result()))
        await configure(call, face=True, opted_in=False)  # camera consent without the emotion opt-in counts for nothing
        assert not call.session.face_allowed()


@pytest.mark.asyncio
async def test_the_camera_stays_off_when_the_server_switch_is_off(monkeypatch):
    monkeypatch.setattr(session_module, "FACE_SERVER_ENABLED", False)
    async with Call(["x"]) as call:
        fake = with_emotion(call, FakeEmotion(result()))
        ready = await configure(call, face=True)
        assert ready["emotion"]["face"] is False
        assert await call.session.video_frame(JPEG) == {"refused": "no_consent"}
        assert getattr(fake, "frames", []) == []


@pytest.mark.asyncio
async def test_a_turns_time_window_is_handed_to_the_estimate_only_with_the_camera_allowed(monkeypatch):
    monkeypatch.setattr(session_module, "FACE_SERVER_ENABLED", True)
    async with Call(["I have been feeling really low lately."]) as call:
        fake = with_emotion(call, FakeEmotion(result()), CueLlm())
        await configure(call, face=True)
        await call.speak()
        await call.until("tts.end")
        window = fake.finalized[0]["face_window"]
        assert window and window[0] < window[1]  # [turn start - 1 s, turn end + 0.5 s] on this server's clock (the test streams faster than real time)

    async with Call(["I have been feeling really low lately."]) as call:
        fake = with_emotion(call, FakeEmotion(result()), CueLlm())
        await configure(call, face=False)
        await call.speak()
        await call.until("tts.end")
        assert fake.finalized[0]["face_window"] is None
