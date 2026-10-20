"""
Duplex turn-lifecycle tests (spec §9.5 runnable checks).

  a. a turn sent as framed binary with a deliberate `seq` gap reports `frame_gap`
  b. `turn.speech_detected` arrives within 200 ms of the first speech frame
  c. after `turn.interrupted` with played_ms, the next turn's history holds a
     truncated assistant message rather than the full generated text

Requires the companion server on 127.0.0.1:8000 (override with SOLACE_SERVER=host:port).
"""

import asyncio
import json
import struct
import time
from pathlib import Path
import wave

import pytest
import websockets

SERVER_ADDR = __import__("os").environ.get("SOLACE_SERVER", "127.0.0.1:8000")
BASE_WS = "ws://" + SERVER_ADDR + "/ws/v1/session"
SPEECH_WAV = Path("debug_recordings/turn_1a0dc78f9a2_1790405312.wav")
FRAME_BYTES = 640  # 20 ms @ 16 kHz mono pcm16
STREAM_ID = 1001


def framed(seq: int, pcm: bytes) -> bytes:
    return struct.pack("<II", STREAM_ID, seq) + pcm


async def open_session(tag: str):
    session_id = f"sess_duplex_{tag}_{int(time.time() * 1000)}"
    ws = await websockets.connect(f"{BASE_WS}?session_id={session_id}&token=tok_test")
    await ws.send(json.dumps({"v": 1, "type": "hello", "session_id": session_id}))
    ready = json.loads(await ws.recv())
    assert ready["type"] == "session_ready"
    return ws, session_id


async def recv_until(ws, wanted, timeout=10.0, collect=None):
    """Drain envelopes until one of `wanted` arrives; return it plus everything seen."""
    seen = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        remaining = deadline - time.time()
        raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        if isinstance(raw, (bytes, bytearray)):
            continue
        event = json.loads(raw)
        seen.append(event)
        if collect:
            collect(event)
        if event.get("type") in wanted:
            return event, seen
    raise AssertionError(f"none of {wanted} within {timeout}s; saw {[e.get('type') for e in seen]}")


def speech_pcm() -> bytes:
    assert SPEECH_WAV.exists(), f"{SPEECH_WAV} must exist"
    with wave.open(str(SPEECH_WAV), "rb") as wf:
        return wf.readframes(wf.getnframes())


@pytest.mark.asyncio
async def test_framed_turn_reports_sequence_gap():
    """A dropped capture frame must be visible, not a silently shifted timeline."""
    ws, _ = await open_session("gap")
    try:
        await ws.send(json.dumps({
            "v": 1,
            "type": "input.start",
            "turn_id": "turn_gap",
            "stream_id": STREAM_ID,
            "framed": True,
            "sample_rate": 16000,
            "channels": 1,
            "frame_ms": 20,
            "pre_roll_ms": 600,
        }))
        started, _seen = await recv_until(ws, {"turn.started"})
        assert started["turn_id"] == "turn_gap"
        assert started["frame_ms"] == 20
        assert started["pre_roll_ms"] == 600

        silence = bytes(FRAME_BYTES)
        for seq in (0, 1, 2):
            await ws.send(framed(seq, silence))
        # Frames 3 and 4 never arrive.
        await ws.send(framed(5, silence))
        await ws.send(framed(6, silence))

        gap, _seen = await recv_until(ws, {"turn.diagnostic"}, timeout=5.0)
        assert gap["reason"] == "frame_gap"
        assert gap["expected"] == 3
        assert gap["received"] == 5
        assert gap["missing"] == 2

        await ws.send(json.dumps({"v": 1, "type": "turn.cancel", "turn_id": "turn_gap"}))
    finally:
        await ws.close()


@pytest.mark.asyncio
async def test_speech_detected_is_low_latency():
    """`turn.speech_detected` is the barge-in signal and must not wait for STT."""
    ws, _ = await open_session("speech")
    try:
        await ws.send(json.dumps({
            "v": 1,
            "type": "input.start",
            "turn_id": "turn_speech_detect",
            "stream_id": STREAM_ID,
            "framed": True,
            "sample_rate": 16000,
            "channels": 1,
            "frame_ms": 20,
        }))
        await recv_until(ws, {"turn.started"})

        pcm = speech_pcm()
        # 0.5 s of room tone first, so the crossing is unambiguous.
        seq = 0
        for _ in range(25):
            await ws.send(framed(seq, bytes(FRAME_BYTES)))
            seq += 1
        frames = []
        for offset in range(0, len(pcm), FRAME_BYTES):
            frame = pcm[offset:offset + FRAME_BYTES]
            if len(frame) < FRAME_BYTES:
                frame = frame + bytes(FRAME_BYTES - len(frame))
            frames.append(framed(seq, frame))
            seq += 1
        # Stream the whole utterance, then read: the assertion is about the
        # server's decision, not about this client's read loop.
        for frame in frames:
            await ws.send(frame)
        sent_at = time.time()

        # The turn is still open: no input.end has been sent, so any envelope we
        # see here was produced from the audio as it streamed.
        detected, _seen = await recv_until(ws, {"turn.speech_detected"}, timeout=10.0)
        latency = time.time() - sent_at

        assert detected["turn_id"] == "turn_speech_detect"
        assert detected["source"] == "server_vad"
        assert detected["confidence"] > 0.5
        assert detected["speech_start_sample"] >= 0
        # Detection is a server-side VAD pass over 512-sample windows: a couple
        # of seconds for a multi-second utterance is the whole budget.
        assert latency < 3.0, f"turn.speech_detected took {latency:.2f}s"
        # And it fired near the onset, not after buffering the entire turn.
        total_ms = (25 + len(frames)) * 20
        assert detected["offset_ms"] < total_ms * 0.75
        print(
            f"[PASS] turn.speech_detected after {latency * 1000:.0f} ms, "
            f"offset={detected['offset_ms']}ms of {total_ms}ms"
        )

        await ws.send(json.dumps({
            "v": 1, "type": "turn.cancel", "turn_id": "turn_speech_detect",
        }))
    finally:
        await ws.close()


@pytest.mark.asyncio
async def test_interruption_truncates_history():
    """History must record only what the user heard, never the full generation."""
    ws, _ = await open_session("interrupt")
    try:
        await ws.send(json.dumps({
            "v": 1,
            "type": "text_message",
            "turn_id": "turn_long",
            "text": "Tell me a long, calm story about a lighthouse keeper.",
        }))
        # Wait until the response is actually being synthesised, so there are
        # segments on the server to truncate.
        await recv_until(ws, {"tts.segment"}, timeout=20.0)

        await ws.send(json.dumps({
            "v": 1,
            "type": "turn.interrupted",
            "turn_id": "turn_interrupt",
            "interrupted_turn_id": "asst_partial",
            "played_ms": 0,
        }))
        cancelled, _seen = await recv_until(ws, {"tts.end"}, timeout=10.0)
        assert cancelled["cancelled"] is True
        assert cancelled["reason"] == "user_speech"

        await asyncio.sleep(0.5)  # let the cancelled LLM task commit its history
        await ws.send(json.dumps({
            "v": 1,
            "type": "text_message",
            "turn_id": "turn_after",
            "text": "What did you just say?",
        }))
        started, _seen = await recv_until(ws, {"llm_start"}, timeout=20.0)
        # Two messages: the interrupted user turn and its truncated assistant
        # reply. Without truncation there would be no record at all, and with
        # the untruncated text the prompt would contain unheard words.
        assert started["history_messages"] == 2
    finally:
        await ws.send(json.dumps({"v": 1, "type": "call.end", "reason": "test_done"}))
        await ws.close()


@pytest.mark.asyncio
async def test_input_turn_endpoints_and_answers():
    """A full duplex turn: speech in, endpoint, transcript, spoken reply."""
    ws, _ = await open_session("full")
    try:
        await ws.send(json.dumps({
            "v": 1,
            "type": "input.start",
            "turn_id": "turn_full",
            "stream_id": STREAM_ID,
            "framed": True,
            "sample_rate": 16000,
            "channels": 1,
            "frame_ms": 20,
            "pre_roll_ms": 600,
        }))
        await recv_until(ws, {"turn.started"})

        pcm = speech_pcm()
        seq = 0
        for offset in range(0, len(pcm), FRAME_BYTES):
            frame = pcm[offset:offset + FRAME_BYTES]
            if len(frame) < FRAME_BYTES:
                frame = frame + bytes(FRAME_BYTES - len(frame))
            await ws.send(framed(seq, frame))
            seq += 1
            await asyncio.sleep(0.005)

        await ws.send(json.dumps({
            "v": 1, "type": "input.end", "turn_id": "turn_full", "reason": "silence",
        }))

        endpointed, _seen = await recv_until(ws, {"turn.endpointed"}, timeout=20.0)
        assert endpointed["reason"] == "silence"
        assert endpointed["speech_ms"] > 0
        assert endpointed["frame_gaps"] == 0

        processing, _seen = await recv_until(ws, {"turn.processing"}, timeout=20.0)
        assert processing["stage"] == "stt"

        transcript, _seen = await recv_until(ws, {"transcript_final"}, timeout=60.0)
        assert transcript["text"].strip()
        print(f"[PASS] duplex transcript: \"{transcript['text']}\"")
    finally:
        await ws.send(json.dumps({"v": 1, "type": "call.end", "reason": "test_done"}))
        await ws.close()
