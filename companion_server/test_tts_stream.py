"""Integration test suite for Phase 6 TTS audio streaming and WebSocket protocol."""

import json
import struct
import sys
import unittest
from pathlib import Path

# Add companion_server to path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from starlette.testclient import TestClient
from main import app, tts, llm


class TestTtsStreaming(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ensure LLM and TTS are ready
        llm.initialize()
        tts.warmup()
        cls.client = TestClient(app)

    def test_01_healthz_and_models_endpoints(self):
        """Verify /healthz, /v1/models, and /v1/voices contain Phase 6 TTS information."""
        resp = self.client.get("/healthz")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["phase"], 6)
        self.assertEqual(data["phase_name"], "local_tts_audio_streaming")
        self.assertTrue(data["tts_ready"])
        self.assertIn("tts_engine", data)
        self.assertGreater(data["tts_sample_rate"], 0)

        # /v1/models
        resp = self.client.get("/v1/models")
        self.assertEqual(resp.status_code, 200)
        models_data = resp.json()
        self.assertIn("tts", models_data)
        self.assertTrue(models_data["tts"]["ready"])
        self.assertGreaterEqual(len(models_data["tts"]["voices"]), 1)

        # /v1/voices
        resp = self.client.get("/v1/voices")
        self.assertEqual(resp.status_code, 200)
        voices_data = resp.json()
        self.assertIn("voices", voices_data)
        self.assertIn("default_voice", voices_data)

    def test_02_session_handshake_and_configure(self):
        """Verify hello handshake and session.configure message flow."""
        with self.client.websocket_connect("/ws/v1/session") as ws:
            # 1. Send hello
            ws.send_text(json.dumps({"type": "hello", "session_id": "test_sess_01"}))
            ready_msg = ws.receive_json()
            self.assertEqual(ready_msg["type"], "session_ready")
            self.assertEqual(ready_msg["session_id"], "test_sess_01")
            self.assertIn("tts", ready_msg)
            self.assertTrue(ready_msg["tts"]["enabled"])

            # 2. Send session.configure
            ws.send_text(json.dumps({
                "type": "session.configure",
                "mode": "duplex_call",
                "tts": {
                    "enabled": True,
                    "voice_id": "af_heart",
                    "speed": 0.95
                },
                "audio": {
                    "mic_sample_rate": 16000,
                    "playback_sample_rate": 24000,
                    "codec": "pcm_s16le"
                }
            }))
            conf_ready = ws.receive_json()
            self.assertEqual(conf_ready["type"], "session.ready")
            self.assertEqual(conf_ready["mode"], "duplex_call")
            self.assertEqual(conf_ready["tts"]["voice_id"], "af_heart")

    def test_03_text_message_triggers_tts_stream(self):
        """Verify text message triggers LLM tokens and 8-byte framed PCM binary audio stream."""
        with self.client.websocket_connect("/ws/v1/session") as ws:
            # Handshake
            ws.send_text(json.dumps({"type": "hello", "session_id": "test_tts_stream"}))
            ws.receive_json()

            # Send text message
            ws.send_text(json.dumps({
                "type": "text_message",
                "turn_id": "turn_tts_test",
                "text": "Hello, I am testing voice synthesis."
            }))

            # Expect echo
            echo = ws.receive_json()
            self.assertEqual(echo["type"], "echo")

            # Expect llm_start
            llm_start = ws.receive_json()
            self.assertEqual(llm_start["type"], "llm_start")
            utterance_id = llm_start.get("utterance_id")
            audio_stream_id = llm_start.get("audio_stream_id")
            self.assertIsNotNone(utterance_id)
            self.assertIsNotNone(audio_stream_id)

            # Expect tts.start
            tts_start = ws.receive_json()
            self.assertEqual(tts_start["type"], "tts.start")
            self.assertEqual(tts_start["utterance_id"], utterance_id)
            self.assertEqual(tts_start["audio_stream_id"], audio_stream_id)
            self.assertEqual(tts_start["codec"], "pcm_s16le")
            self.assertGreater(tts_start["sample_rate"], 0)

            binary_frames = []
            llm_chunks = []
            got_llm_done = False
            got_tts_end = False
            seq_counter = 0

            # Drain messages until both llm_done and tts.end are received
            for _ in range(300):
                if got_llm_done and got_tts_end:
                    break
                raw = ws.receive()
                if "bytes" in raw and raw["bytes"] is not None:
                    frame = raw["bytes"]
                    self.assertGreaterEqual(len(frame), 8)
                    stream_id, seq = struct.unpack("<II", frame[:8])
                    self.assertEqual(stream_id, audio_stream_id)
                    self.assertEqual(seq, seq_counter)
                    seq_counter += 1
                    payload = frame[8:]
                    self.assertTrue(len(payload) > 0)
                    self.assertEqual(len(payload) % 2, 0)  # 16-bit PCM = even byte count
                    binary_frames.append(frame)
                elif "text" in raw and raw["text"] is not None:
                    event = json.loads(raw["text"])
                    if event["type"] == "llm_chunk":
                        llm_chunks.append(event.get("delta", ""))
                    elif event["type"] == "llm_done":
                        got_llm_done = True
                        self.assertEqual(event["utterance_id"], utterance_id)
                    elif event["type"] == "tts.end":
                        got_tts_end = True
                        self.assertEqual(event["audio_stream_id"], audio_stream_id)
                        self.assertFalse(event["cancelled"])
                        self.assertEqual(event["reason"], "complete")
                        self.assertGreater(event["total_frames"], 0)

            self.assertTrue(got_llm_done, "Expected llm_done event")
            self.assertTrue(got_tts_end, "Expected tts.end event")
            self.assertGreater(len(binary_frames), 0, "Expected at least one binary audio frame")
            self.assertGreater(len(llm_chunks), 0, "Expected LLM text tokens")

    def test_04_speech_cancel_stops_tts_leaves_llm_streaming(self):
        """Verify speech.cancel stops audio synthesis/streaming while LLM text streaming completes."""
        with self.client.websocket_connect("/ws/v1/session") as ws:
            ws.send_text(json.dumps({"type": "hello", "session_id": "test_speech_cancel"}))
            ws.receive_json()

            ws.send_text(json.dumps({
                "type": "text_message",
                "turn_id": "turn_cancel_test",
                "text": "Tell me a soothing story about peaceful mountain winds and quiet pine trees."
            }))

            ws.receive_json()  # echo
            llm_start = ws.receive_json()
            tts_start = ws.receive_json()
            audio_stream_id = tts_start["audio_stream_id"]

            # Send speech.cancel immediately
            ws.send_text(json.dumps({
                "type": "speech.cancel",
                "cancel_tts": True,
                "cancel_llm": False,
                "reason": "user_tapped_cancel_voice"
            }))

            got_tts_cancelled = False
            got_llm_done = False
            chunks_after_cancel = []

            for _ in range(300):
                if got_tts_cancelled and got_llm_done:
                    break
                raw = ws.receive()
                if "text" in raw and raw["text"] is not None:
                    event = json.loads(raw["text"])
                    if event["type"] == "tts.end":
                        self.assertTrue(event["cancelled"])
                        self.assertEqual(event["audio_stream_id"], audio_stream_id)
                        got_tts_cancelled = True
                    elif event["type"] == "llm_chunk":
                        chunks_after_cancel.append(event.get("delta", ""))
                    elif event["type"] == "llm_done":
                        got_llm_done = True

            self.assertTrue(got_tts_cancelled, "Expected tts.end with cancelled=True")
            self.assertTrue(got_llm_done, "Expected llm_done to finish despite TTS cancellation")
            self.assertGreater(len(chunks_after_cancel), 0, "Expected LLM chunks to stream after voice cancel")

    def test_05_call_barge_in_aborts_both_llm_and_tts(self):
        """Verify call.barge_in immediately aborts both LLM generation and TTS worker."""
        with self.client.websocket_connect("/ws/v1/session") as ws:
            ws.send_text(json.dumps({
                "type": "session.configure",
                "mode": "duplex_call"
            }))
            ws.receive_json()  # session.ready

            ws.send_text(json.dumps({
                "type": "text_message",
                "turn_id": "turn_barge_in_test",
                "text": "Please provide an extensive explanation of gentle breathing exercises."
            }))

            ws.receive_json()  # echo
            ws.receive_json()  # llm_start
            ws.receive_json()  # tts.start

            # Send call.barge_in
            ws.send_text(json.dumps({
                "type": "call.barge_in",
                "turn_id": "turn_barge_in_test",
                "reason": "vad_speech_detected",
                "cancel_tts": True,
                "cancel_llm": True
            }))

            # Expect call.state listening
            call_state = ws.receive_json()
            self.assertEqual(call_state["type"], "call.state")
            self.assertEqual(call_state["state"], "listening")

            got_tts_cancelled = False
            for _ in range(50):
                if got_tts_cancelled:
                    break
                raw = ws.receive()
                if "text" in raw and raw["text"] is not None:
                    event = json.loads(raw["text"])
                    if event["type"] == "tts.end":
                        self.assertTrue(event["cancelled"])
                        self.assertIn(event["reason"], ["vad_speech_detected", "barge_in"])
                        got_tts_cancelled = True

            self.assertTrue(got_tts_cancelled, "Expected tts.end with cancelled=True and reason=vad_speech_detected")

    def test_06_session_configure_toggle_tts_off(self):
        """Verify that disabling TTS produces only text LLM chunks without tts.start or binary audio."""
        with self.client.websocket_connect("/ws/v1/session") as ws:
            # Disable TTS
            ws.send_text(json.dumps({
                "type": "session.configure",
                "tts": {"enabled": False}
            }))
            ws.receive_json()  # session.ready

            ws.send_text(json.dumps({
                "type": "text_message",
                "turn_id": "turn_no_tts",
                "text": "Hello text only."
            }))

            echo = ws.receive_json()
            self.assertEqual(echo["type"], "echo")

            llm_start = ws.receive_json()
            self.assertEqual(llm_start["type"], "llm_start")
            self.assertIsNone(llm_start.get("audio_stream_id"))

            binary_frames = 0
            got_llm_done = False
            got_tts_start = False

            for _ in range(100):
                if got_llm_done:
                    break
                raw = ws.receive()
                if "bytes" in raw and raw["bytes"] is not None:
                    binary_frames += 1
                elif "text" in raw and raw["text"] is not None:
                    event = json.loads(raw["text"])
                    if event["type"] == "tts.start":
                        got_tts_start = True
                    elif event["type"] == "llm_done":
                        got_llm_done = True

            self.assertFalse(got_tts_start, "tts.start should not be emitted when TTS is disabled")
            self.assertEqual(binary_frames, 0, "No binary audio frames should be emitted when TTS is disabled")
            self.assertTrue(got_llm_done, "LLM should complete normally when TTS is disabled")


if __name__ == "__main__":
    unittest.main()
