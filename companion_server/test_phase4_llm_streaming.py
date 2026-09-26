"""Comprehensive Phase 4 test suite: Local LLM Streaming Response over WebSocket.

Tests:
1. Health endpoint reports Phase 4 and LLM readiness.
2. Text message triggers real-time token-by-token LLM streaming (llm_start -> llm_chunk* -> llm_done).
3. Transcribed voice note triggers automatic LLM streaming reply.
"""

import asyncio
import json
import time
from pathlib import Path
import wave
import pytest
import websockets
import httpx


SERVER_HTTP_URL = "http://127.0.0.1:8000"
SERVER_WS_URL = "ws://127.0.0.1:8000/ws/v1/session"


@pytest.mark.asyncio
async def test_healthz_phase4():
    """Verify that companion server reports Phase 4 with LLM ready."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{SERVER_HTTP_URL}/healthz")
        assert resp.status_code == 200, f"Healthz failed: {resp.text}"
        data = resp.json()
        print("\n--- Healthz Response ---")
        print(json.dumps(data, indent=2))
        assert data["status"] == "ok"
        assert data["phase"] == 4
        assert data["phase_name"] == "local_llm_streaming"
        assert data["llm_ready"] is True, "LLM should be initialized and ready"
        assert "llm_model" in data


@pytest.mark.asyncio
async def test_text_message_llm_streaming():
    """Verify that sending a text message triggers real LLM streaming tokens."""
    async with websockets.connect(SERVER_WS_URL) as ws:
        # 1. Handshake
        await ws.send(json.dumps({
            "v": 1,
            "type": "hello",
            "client": "test-client",
            "session_id": "test_sess_p4_text"
        }))
        hello_resp = json.loads(await ws.recv())
        assert hello_resp["type"] == "session_ready"

        # 2. Send text message
        turn_id = f"text_{int(time.time())}"
        user_text = "I feel so anxious and overwhelmed today."
        print(f"\n--- Testing Text Message LLM Streaming [{turn_id}] ---")
        print(f"User: \"{user_text}\"")

        await ws.send(json.dumps({
            "v": 1,
            "type": "text_message",
            "turn_id": turn_id,
            "text": user_text,
            "ts": int(time.time() * 1000)
        }))

        # 3. Expect echo
        echo_msg = json.loads(await ws.recv())
        assert echo_msg["type"] == "echo"
        assert echo_msg["turn_id"] == turn_id

        # 4. Expect llm_start
        start_msg = json.loads(await ws.recv())
        assert start_msg["type"] == "llm_start"
        assert start_msg["reply_to"] == turn_id
        asst_turn_id = start_msg["turn_id"]
        print(f"LLM Start received: asst_turn_id={asst_turn_id}, model={start_msg.get('model')}")

        # 5. Collect llm_chunk tokens until llm_done
        chunks = []
        t0 = time.time()
        print("Companion reply: ", end="", flush=True)

        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=25.0)
            evt = json.loads(raw)
            if evt["type"] == "llm_chunk":
                delta = evt.get("delta", "")
                chunks.append(delta)
                print(delta, end="", flush=True)
            elif evt["type"] == "llm_done":
                print(f"\nLLM Done received in {time.time() - t0:.2f}s!")
                assert evt["turn_id"] == asst_turn_id
                assert evt["reply_to"] == turn_id
                full_text = evt.get("text", "")
                assert len(full_text) > 0
                assert "".join(chunks) == full_text
                print(f"Total tokens: {evt.get('tokens')}, TTFT: {evt.get('ttft_ms')}ms")
                break
            else:
                print(f"\nUnexpected event: {evt}")


@pytest.mark.asyncio
async def test_voice_note_transcript_and_llm_streaming():
    """Verify that a recorded voice note transcribes and triggers LLM streaming reply."""
    # Find existing speech WAV in debug_recordings
    recordings_dir = Path(__file__).resolve().parent / "debug_recordings"
    wav_files = list(recordings_dir.glob("turn_*.wav"))
    if not wav_files:
        print("No WAV files found in debug_recordings; skipping voice audio test")
        return

    test_wav = wav_files[0]
    print(f"\n--- Testing Voice Note -> Transcription -> LLM Stream with {test_wav.name} ---")

    with wave.open(str(test_wav), "rb") as wf:
        sr = wf.getframerate()
        ch = wf.getnchannels()
        pcm_bytes = wf.readframes(wf.getnframes())

    async with websockets.connect(SERVER_WS_URL) as ws:
        # Handshake
        await ws.send(json.dumps({"v": 1, "type": "hello", "client": "test-client"}))
        ready = json.loads(await ws.recv())
        assert ready["type"] == "session_ready"

        turn_id = f"voice_p4_{int(time.time())}"

        # 1. audio_start
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_start",
            "turn_id": turn_id,
            "sample_rate": sr,
            "channels": ch,
            "frame_ms": 100
        }))
        ack = json.loads(await ws.recv())
        assert ack["type"] == "audio_ack"

        # 2. Stream chunks
        chunk_size = int(sr * ch * 2 * 0.1)  # 100ms
        for i in range(0, len(pcm_bytes), chunk_size):
            await ws.send(pcm_bytes[i : i + chunk_size])
            await asyncio.sleep(0.01)

        # 3. audio_end
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_end",
            "turn_id": turn_id,
            "sample_rate": sr
        }))

        # 4. Expect audio_received
        rx_msg = json.loads(await ws.recv())
        assert rx_msg["type"] == "audio_received"

        # 5. Expect transcript_final
        trans_msg = json.loads(await ws.recv())
        assert trans_msg["type"] == "transcript_final"
        print(f"Transcribed voice note: \"{trans_msg.get('text')}\"")

        # 6. Expect LLM start followed by chunks and done
        start_msg = json.loads(await ws.recv())
        assert start_msg["type"] == "llm_start"
        assert start_msg["reply_to"] == turn_id
        print(f"LLM streaming started for turn {turn_id}...")

        chunks = []
        print("Companion reply: ", end="", flush=True)
        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=25.0)
            evt = json.loads(raw)
            if evt["type"] == "llm_chunk":
                delta = evt.get("delta", "")
                chunks.append(delta)
                print(delta, end="", flush=True)
            elif evt["type"] == "llm_done":
                print(f"\nLLM streaming complete! Full reply: \"{evt.get('text')}\"")
                break


if __name__ == "__main__":
    asyncio.run(test_healthz_phase4())
    asyncio.run(test_text_message_llm_streaming())
    asyncio.run(test_voice_note_transcript_and_llm_streaming())
    print("\nALL PHASE 4 TESTS COMPLETED SUCCESSFULLY!")
