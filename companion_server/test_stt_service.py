import wave
import numpy as np
from pathlib import Path
from stt_service import SttService

def test_stt_service():
    service = SttService(model_size="base.en")
    service.initialize()
    assert service.is_ready, "Service should be initialized"

    # Test 1: Real recorded audio file
    wav_path = Path("debug_recordings/turn_1a0dc78f9a2_1790405312.wav")
    assert wav_path.exists(), f"{wav_path} must exist"

    with wave.open(str(wav_path), "rb") as wf:
        pcm_bytes = wf.readframes(wf.getnframes())

    has_speech = service.has_speech(pcm_bytes)
    assert has_speech, "Real recording must have speech detected by Silero VAD"

    text, conf, lang = service.transcribe(pcm_bytes)
    print(f"Test 1 Transcribed: \"{text}\" (confidence={conf:.2f}, lang={lang})")
    assert len(text) > 0, "Transcribed text should not be empty"
    assert conf > 0.5, "Confidence should be reasonable"

    # Test 2: Pure silence
    silence_pcm = bytes(16000 * 2 * 2)  # 2 seconds of pure silence
    has_silence_speech = service.has_speech(silence_pcm)
    assert not has_silence_speech, "Pure silence should have no speech detected"
    print("Test 2 (Silence rejection) PASSED!")

    print("\nAll SttService unit tests PASSED successfully!")

if __name__ == "__main__":
    test_stt_service()
