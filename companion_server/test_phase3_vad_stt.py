"""
Test Suite for Phase 3: VAD + STT Transcription
Tests:
  1. Healthz endpoint verifies phase=3 and stt_ready=True
  2. Stream real speech audio frames over WebSocket and verify 'transcript_final' with text
  3. Stream pure silence frames over WebSocket and verify 'transcript_failed' with reason='silence'
"""

import asyncio
import json
from pathlib import Path
import time
import wave
import requests
import websockets

BASE_HTTP = "http://127.0.0.1:8000"
BASE_WS = "ws://127.0.0.1:8000/ws/v1/session"
SPEECH_WAV = Path("debug_recordings/turn_1a0dc78f9a2_1790405312.wav")

def test_healthz():
    print("--- 1. Testing Healthz Endpoint ---")
    resp = requests.get(f"{BASE_HTTP}/healthz", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    print(f"Healthz: {data}")
    assert data["phase"] == 3
    assert data["phase_name"] == "vad_stt_transcription"
    assert data["stt_ready"] is True
    print("[PASS] Healthz Phase 3 verified!")

async def test_speech_transcription():
    print("\n--- 2. Testing Speech Streaming & Transcription ---")
    assert SPEECH_WAV.exists(), f"{SPEECH_WAV} must exist"

    with wave.open(str(SPEECH_WAV), "rb") as wf:
        total_frames = wf.getnframes()
        pcm_bytes = wf.readframes(total_frames)

    session_id = f"sess_stt_test_{int(time.time())}"
    ws_uri = f"{BASE_WS}?session_id={session_id}&token=tok_test"

    async with websockets.connect(ws_uri) as ws:
        # Hello
        await ws.send(json.dumps({"v": 1, "type": "hello", "session_id": session_id}))
        ready = json.loads(await ws.recv())
        assert ready["type"] == "session_ready"

        # Audio start
        turn_id = f"turn_speech_{int(time.time())}"
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_start",
            "turn_id": turn_id,
            "sample_rate": 16000,
            "channels": 1,
            "frame_ms": 100,
        }))
        ack = json.loads(await ws.recv())
        assert ack["type"] == "audio_ack"

        # Stream chunks (100ms / 3200 bytes each)
        chunk_size = 3200
        for i in range(0, len(pcm_bytes), chunk_size):
            chunk = pcm_bytes[i:i + chunk_size]
            await ws.send(chunk)
            await asyncio.sleep(0.005)

        # Audio end
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_end",
            "turn_id": turn_id,
            "duration_ms": int((len(pcm_bytes) / 32000) * 1000)
        }))

        # Expect audio_received
        received = json.loads(await ws.recv())
        assert received["type"] == "audio_received"
        print(f"Server acknowledged audio: {received['bytes']} bytes")

        # Expect transcript_final
        final_msg = json.loads(await ws.recv())
        print(f"Server transcript event: {final_msg}")
        assert final_msg["type"] == "transcript_final"
        assert final_msg["turn_id"] == turn_id
        assert len(final_msg["text"]) > 0
        assert final_msg["confidence"] > 0.4
        print(f"[PASS] Successfully received transcript_final: \"{final_msg['text']}\"")

async def test_silence_rejection():
    print("\n--- 3. Testing Silence Rejection with VAD ---")
    session_id = f"sess_silence_test_{int(time.time())}"
    ws_uri = f"{BASE_WS}?session_id={session_id}&token=tok_test"

    async with websockets.connect(ws_uri) as ws:
        await ws.send(json.dumps({"v": 1, "type": "hello", "session_id": session_id}))
        await ws.recv()

        turn_id = f"turn_silence_{int(time.time())}"
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_start",
            "turn_id": turn_id,
            "sample_rate": 16000,
            "channels": 1,
            "frame_ms": 100,
        }))
        await ws.recv()

        # Stream 15 frames of pure silence (1.5 seconds)
        silence_frame = bytes(3200)
        for _ in range(15):
            await ws.send(silence_frame)
            await asyncio.sleep(0.005)

        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_end",
            "turn_id": turn_id,
            "duration_ms": 1500
        }))

        # Expect audio_received
        received = json.loads(await ws.recv())
        assert received["type"] == "audio_received"

        # Expect transcript_failed because VAD detected silence
        failed_msg = json.loads(await ws.recv())
        print(f"Server silence event: {failed_msg}")
        assert failed_msg["type"] == "transcript_failed"
        assert failed_msg["reason"] == "silence"
        assert failed_msg["turn_id"] == turn_id
        print(f"[PASS] Silence correctly rejected without unnecessary transcription!")

async def main():
    test_healthz()
    await test_speech_transcription()
    await test_silence_rejection()
    print("\n=== ALL PHASE 3 VAD + STT BACKEND TESTS PASSED! ===")

if __name__ == "__main__":
    asyncio.run(main())
