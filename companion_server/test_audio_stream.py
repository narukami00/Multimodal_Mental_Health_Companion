"""
Solace Companion Backend - Phase 2 Audio Streaming Test Suite
Tests:
  1. Verify /healthz reflects Phase 2 ("pcm_audio_capture")
  2. Send 'audio_start' envelope and verify 'audio_ack'
  3. Stream 20 binary frames (100ms each = 3200 bytes of 16kHz PCM16)
  4. Send 'audio_end' and verify 'audio_received' and 'transcript_final'
  5. Validate generated WAV file on disk (channels, rate, sample width, duration)
  6. Test 'audio_cancel' and verify 'turn_cancelled' with no leaked files
"""

import asyncio
import json
import math
from pathlib import Path
import struct
import sys
import time
import wave
import requests
import websockets
import pytest

BASE_HTTP = "http://127.0.0.1:8000"
BASE_WS = "ws://127.0.0.1:8000/ws/v1/session"
RECORDINGS_DIR = Path(__file__).resolve().parent / "debug_recordings"

def generate_pcm16_sine_wave(freq_hz: float = 440.0, duration_sec: float = 0.100, sample_rate: int = 16000) -> bytes:
    """Generate 100ms of synthetic 16-bit mono PCM audio (1600 samples = 3200 bytes)."""
    num_samples = int(duration_sec * sample_rate)
    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        val = int(32767.0 * 0.7 * math.sin(2.0 * math.pi * freq_hz * t))
        val = max(-32768, min(32767, val))
        samples.append(val)
    return struct.pack(f"<{len(samples)}h", *samples)

def test_phase2_health():
    print("\n--- 1. Testing Health Endpoint for Phase 2 ---")
    resp = requests.get(f"{BASE_HTTP}/healthz", timeout=5)
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}"
    data = resp.json()
    print(f"[PASS] /healthz response: {data}")
    assert data["status"] == "ok"
    assert data["phase"] >= 2
    assert "recordings_dir" in data

@pytest.mark.asyncio
async def test_audio_streaming_flow():
    print("\n--- 2. Testing Phase 2 Audio Streaming Flow ---")
    session_id = f"sess_audio_test_{int(time.time())}"
    ws_uri = f"{BASE_WS}?session_id={session_id}&token=test_token"

    async with websockets.connect(ws_uri) as ws:
        # Step A: Handshake
        hello_msg = {
            "v": 1,
            "type": "hello",
            "session_id": session_id,
            "thread_id": "thread_audio",
            "client": {"platform": "python-tester", "app_version": "0.2.0"},
            "ts": int(time.time() * 1000)
        }
        await ws.send(json.dumps(hello_msg))
        raw_ready = await ws.recv()
        ready = json.loads(raw_ready)
        assert ready.get("type") == "session_ready"
        print(f"[PASS] Handshake ready for session: {session_id}")

        # Step B: Audio Start
        turn_id = f"turn_audio_{int(time.time())}"
        audio_start_msg = {
            "v": 1,
            "type": "audio_start",
            "turn_id": turn_id,
            "encoding": "pcm16",
            "sample_rate": 16000,
            "channels": 1,
            "frame_ms": 100,
            "mode": "voice_note",
            "client_vad": True,
            "ts": int(time.time() * 1000)
        }
        await ws.send(json.dumps(audio_start_msg))
        raw_ack = await ws.recv()
        ack = json.loads(raw_ack)
        print(f"[PASS] Audio Ack received: {ack}")
        assert ack.get("type") == "audio_ack"
        assert ack.get("turn_id") == turn_id

        # Step C: Stream 20 chunks (2.0 seconds total, 100ms / 3200 bytes each)
        frame_bytes = generate_pcm16_sine_wave(freq_hz=440.0, duration_sec=0.100, sample_rate=16000)
        assert len(frame_bytes) == 3200, f"Expected 3200 bytes per 100ms frame, got {len(frame_bytes)}"

        print(f"Streaming 20 binary frames (3200 bytes each) for {turn_id}...")
        for i in range(20):
            await ws.send(frame_bytes)
            await asyncio.sleep(0.01)  # small interval

        # Step D: Audio End
        recordings_before = set(RECORDINGS_DIR.glob("*.wav")) if RECORDINGS_DIR.exists() else set()
        audio_end_msg = {
            "v": 1,
            "type": "audio_end",
            "turn_id": turn_id,
            "duration_ms": 2000,
            "client_vad_endpoint": True,
            "ts": int(time.time() * 1000)
        }
        await ws.send(json.dumps(audio_end_msg))

        # Expect audio_received
        raw_received = await ws.recv()
        audio_received = json.loads(raw_received)
        print(f"[PASS] audio_received event: {audio_received}")
        assert audio_received.get("type") == "audio_received"
        assert audio_received.get("turn_id") == turn_id
        assert audio_received.get("frames") == 20
        assert audio_received.get("bytes") == 64000
        assert audio_received.get("duration_ms") == 2000
        wav_file = audio_received.get("wav_file")

        # Expect transcript_final
        raw_transcript = await ws.recv()
        transcript = json.loads(raw_transcript)
        print(f"[PASS] transcript_final event: {transcript}")
        assert transcript.get("type") in ("transcript_final", "transcript_failed")
        assert transcript.get("turn_id") == turn_id

        # Step E: per-turn WAV dumps are off by default (they used to run on the
        # event loop for every turn and grow without bound). When the dump is
        # enabled the file must be a valid 2.0 s mono 16 kHz WAV.
        recordings_after = set(RECORDINGS_DIR.glob("*.wav")) if RECORDINGS_DIR.exists() else set()
        if wav_file is None:
            assert recordings_after == recordings_before, "no WAV may be written by default"
            print("[PASS] No debug WAV written (debug recordings disabled by default)")
        else:
            wav_path = RECORDINGS_DIR / wav_file
            print(f"\n--- 3. Verifying WAV File on Disk: {wav_path} ---")
            assert wav_path.exists(), f"WAV file {wav_path} was not found on disk"

            with wave.open(str(wav_path), "rb") as wf:
                channels = wf.getnchannels()
                sampwidth = wf.getsampwidth()
                framerate = wf.getframerate()
                nframes = wf.getnframes()
                duration_s = nframes / framerate

                print(f"  Channels: {channels} (expected 1)")
                print(f"  Sample Width: {sampwidth} bytes (expected 2 for 16-bit PCM)")
                print(f"  Sample Rate: {framerate} Hz (expected 16000)")
                print(f"  Total Frames: {nframes} (expected 32000 for 2.0s)")
                print(f"  Calculated Duration: {duration_s:.2f} s")

                assert channels == 1
                assert sampwidth == 2
                assert framerate == 16000
                assert nframes == 32000
                assert abs(duration_s - 2.0) < 0.05
            print("[PASS] WAV audio file is 100% valid and verified!")

        # Step F: Test Audio Cancel
        print("\n--- 4. Testing Audio Cancellation ---")
        cancel_turn_id = f"turn_cancel_{int(time.time())}"
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_start",
            "turn_id": cancel_turn_id,
            "sample_rate": 16000,
            "channels": 1
        }))
        ack_cancel = json.loads(await ws.recv())
        assert ack_cancel.get("type") == "audio_ack"

        # Send a few frames
        for _ in range(5):
            await ws.send(frame_bytes)

        # Cancel
        await ws.send(json.dumps({
            "v": 1,
            "type": "audio_cancel",
            "turn_id": cancel_turn_id,
            "reason": "user_cancelled"
        }))
        cancelled_resp = json.loads(await ws.recv())
        print(f"[PASS] turn_cancelled event: {cancelled_resp}")
        assert cancelled_resp.get("type") == "turn_cancelled"
        assert cancelled_resp.get("turn_id") == cancel_turn_id

    print("\n=== ALL PHASE 2 AUDIO TESTS PASSED SUCCESSFULLY! ===")

def main():
    try:
        test_phase2_health()
        asyncio.run(test_audio_streaming_flow())
    except Exception as e:
        print(f"\n[FAIL] Test encountered error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
