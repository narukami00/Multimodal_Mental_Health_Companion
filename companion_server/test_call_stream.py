"""End-to-end live-call test with real models and real recorded audio.

A synthetic caller does what the phone does: after `call.listen` it streams the
microphone continuously in 20 ms frames at real-time pace, with a real room-noise
recording around a real utterance. The server alone must find the speech, end the
turn, transcribe, answer and speak.

Needs the companion server (default 127.0.0.1:8000, override with SOLACE_SERVER)
and the recordings in `debug_recordings/`.
"""

import asyncio
import json
import os
import struct
import time
import wave
from pathlib import Path

import pytest
import websockets

SERVER_ADDR = os.environ.get("SOLACE_SERVER", "127.0.0.1:8000")
BASE_WS = "ws://" + SERVER_ADDR + "/ws/v1/session"
RECORDINGS = Path("debug_recordings")
FRAME_BYTES = 640  # 20 ms @ 16 kHz mono pcm16
STREAM_ID = 1001


def _first(pattern: str) -> Path:
    matches = sorted(RECORDINGS.glob(pattern))
    if not matches:
        pytest.skip(f"recording {pattern} not available")
    return matches[0]


def _pcm(path: Path) -> bytes:
    with wave.open(str(path), "rb") as wf:
        assert wf.getframerate() == 16000
        return wf.readframes(wf.getnframes())


def room_noise(ms: int) -> bytes:
    """Real phone-mic room noise (RMS ~250-400 LSB), looped to length."""
    noise = _pcm(_first("call_1790427497147_*.wav"))
    need = ms * 32
    return (noise * (need // len(noise) + 1))[:need]


def utterance() -> bytes:
    """'I am not feeling okay' - a real recording from the phone."""
    return _pcm(_first("turn_1a0dcae27f1_*.wav"))


class Caller:
    def __init__(self, ws) -> None:
        self.ws = ws
        self.seq = 0
        self.events = []
        self.audio_frames = 0
        self.first_audio_at = None

    async def read_forever(self) -> None:
        try:
            async for raw in self.ws:
                if isinstance(raw, (bytes, bytearray)):
                    self.audio_frames += 1
                    if self.first_audio_at is None:
                        self.first_audio_at = time.monotonic()
                    continue
                event = json.loads(raw)
                event["_at"] = time.monotonic()
                self.events.append(event)
        except websockets.ConnectionClosed:
            pass

    async def send_audio(self, pcm: bytes, speed: float = 1.0) -> None:
        """Stream at real-time pace on an absolute schedule.

        Sleeping a fixed 20 ms per frame runs about 1.5x slow on Windows, whose
        timer rounds up to ~15 ms; a schedule catches up instead of drifting.
        """
        start = time.monotonic()
        for n, offset in enumerate(range(0, len(pcm), FRAME_BYTES), start=1):
            frame = pcm[offset:offset + FRAME_BYTES]
            frame += bytes(FRAME_BYTES - len(frame))
            await self.ws.send(struct.pack("<II", STREAM_ID, self.seq) + frame)
            self.seq += 1
            delay = start + n * 0.02 / speed - time.monotonic()
            if delay > 0:
                await asyncio.sleep(delay)

    def of(self, kind: str):
        return [e for e in self.events if e["type"] == kind]

    async def until(self, kind: str, timeout: float = 30.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = self.of(kind)
            if found:
                return found[0]
            await asyncio.sleep(0.02)
        raise AssertionError(f"no {kind!r} within {timeout}s; saw {[e['type'] for e in self.events]}")


async def start_call(barge_in: bool = False):
    session_id = f"sess_call_{int(time.time() * 1000)}"
    ws = await websockets.connect(f"{BASE_WS}?session_id={session_id}&token=tok_test", max_size=None)
    await ws.send(json.dumps({"v": 1, "type": "hello", "session_id": session_id}))
    assert json.loads(await ws.recv())["type"] == "session_ready"
    await ws.send(json.dumps({"v": 1, "type": "session.configure", "mode": "duplex_call"}))
    await ws.recv()
    caller = Caller(ws)
    reader = asyncio.create_task(caller.read_forever())
    await ws.send(json.dumps({"v": 1, "type": "call.listen", "sample_rate": 16000,
                              "barge_in": barge_in}))
    await caller.until("call.listening", timeout=15)
    return caller, reader


async def end_call(caller: Caller, reader) -> None:
    await caller.ws.send(json.dumps({"v": 1, "type": "call.end", "reason": "test_done"}))
    await caller.ws.close()
    await reader


@pytest.mark.asyncio
async def test_room_noise_alone_never_starts_a_turn():
    """The old client gate turned this into a stream of empty turns."""
    caller, reader = await start_call()
    try:
        await caller.send_audio(room_noise(9000), speed=4.0)
        await asyncio.sleep(0.5)
        assert caller.of("turn.started") == []
        assert caller.of("transcript_final") == []
    finally:
        await end_call(caller, reader)


@pytest.mark.asyncio
async def test_a_real_utterance_in_real_noise_is_heard_and_answered():
    caller, reader = await start_call()
    try:
        await caller.send_audio(room_noise(1000))
        spoke_from = time.monotonic()
        await caller.send_audio(utterance())
        stopped_at = time.monotonic()
        await caller.send_audio(room_noise(2500))  # keeps streaming, as the phone does

        started = await caller.until("turn.started", timeout=5)
        # The recording opens with ~1.7 s of room tone, so the words start about
        # 2.7 s into this stream: onset must be reported within ~0.3 s of that.
        assert started["_at"] - spoke_from < 2.2, "speech onset should be reported almost at once"
        endpointed = await caller.until("turn.endpointed", timeout=10)
        assert endpointed["reason"] == "silence"
        # The turn ends about one endpoint deadline after the last word, never later.
        assert endpointed["_at"] - stopped_at < 2.5

        transcript = await caller.until("transcript_final", timeout=15)
        assert "feeling" in transcript["text"].lower()

        await caller.until("llm_done", timeout=30)
        await caller.until("tts.end", timeout=60)
        assert caller.audio_frames > 0
        latency = caller.of("turn.latency")
        assert latency, "the server should report where the turn's time went"
        print(
            f"\n[LATENCY] user stopped -> first audio {latency[0]['to_first_audio_ms']} ms "
            f"(stt {latency[0]['stt_ms']} ms, llm first token {latency[0]['llm_first_token_ms']} ms, "
            f"tts {latency[0]['tts_first_audio_ms']} ms)"
        )
    finally:
        await end_call(caller, reader)


@pytest.mark.asyncio
async def test_two_turns_in_one_call_both_get_answers():
    caller, reader = await start_call()
    try:
        for n in (1, 2):
            await caller.send_audio(room_noise(800))
            await caller.send_audio(utterance())
            await caller.send_audio(room_noise(1500))
            if n == 1:
                await caller.until("tts.end", timeout=60)
                # Let the first answer finish playing before the second question.
                await asyncio.sleep(8.0)
        deadline = time.monotonic() + 60
        while len(caller.of("transcript_final")) < 2 and time.monotonic() < deadline:
            await asyncio.sleep(0.05)
        assert len(caller.of("transcript_final")) == 2
    finally:
        await end_call(caller, reader)
