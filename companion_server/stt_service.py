import asyncio
import io
import logging
import time
from typing import Dict, List, Optional, Tuple
import wave

import numpy as np
import torch
from faster_whisper import WhisperModel
from silero_vad import load_silero_vad, get_speech_timestamps

logger = logging.getLogger("solace_companion.stt")

class SttService:
    def __init__(self, model_size: str = "base.en"):
        self.model_size = model_size
        self._vad_model = None
        self._whisper_model = None
        self._device = "cpu"
        self._compute_type = "int8"
        self._is_ready = False

    def initialize(self):
        """Pre-load Silero VAD and Whisper model."""
        if self._is_ready:
            return

        logger.info("Initializing Silero VAD...")
        t0 = time.time()
        self._vad_model = load_silero_vad()
        logger.info(f"Silero VAD loaded in {time.time() - t0:.2f}s")

        logger.info(f"Initializing Faster-Whisper ({self.model_size})...")
        t1 = time.time()
        # Attempt CUDA int8 first; verify runtime libraries (cublas, cudnn), fall back to CPU int8
        try:
            import ctranslate2
            if ctranslate2.get_cuda_device_count() > 0:
                try:
                    candidate = WhisperModel(
                        self.model_size,
                        device="cuda",
                        compute_type="int8",
                    )
                    # Dry run 1 frame to verify CUDA shared libraries are present
                    test_wav = io.BytesIO()
                    with wave.open(test_wav, "wb") as wf:
                        wf.setnchannels(1)
                        wf.setsampwidth(2)
                        wf.setframerate(16000)
                        wf.writeframes(bytes(3200))
                    test_wav.seek(0)
                    list(candidate.transcribe(test_wav, beam_size=1)[0])
                    self._whisper_model = candidate
                    self._device = "cuda"
                    logger.info("Faster-Whisper verified running on CUDA (int8)")
                except Exception as cuda_err:
                    logger.warning(f"CUDA runtime library not found ({cuda_err}), falling back to CPU int8")
                    self._whisper_model = None
        except Exception as e:
            logger.warning(f"CTranslate2 CUDA check skipped: {e}")

        if self._whisper_model is None:
            self._whisper_model = WhisperModel(
                self.model_size,
                device="cpu",
                compute_type="int8",
                cpu_threads=4,
            )
            self._device = "cpu"
            logger.info("Faster-Whisper verified running on CPU (int8)")

        logger.info(f"Faster-Whisper model ready in {time.time() - t1:.2f}s")
        self._is_ready = True

    @property
    def is_ready(self) -> bool:
        return self._is_ready

    @property
    def device(self) -> str:
        return self._device

    def detect_speech(self, pcm_bytes: bytes, sample_rate: int = 16000) -> List[Dict[str, int]]:
        """Return list of speech timestamps {'start': int, 'end': int} using Silero VAD."""
        if not self._is_ready:
            self.initialize()

        if len(pcm_bytes) < 3200:  # less than 100ms
            return []

        audio_np = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        wav_tensor = torch.from_numpy(audio_np)
        timestamps = get_speech_timestamps(
            wav_tensor,
            self._vad_model,
            sampling_rate=sample_rate,
            threshold=0.45,
            min_speech_duration_ms=150,
            min_silence_duration_ms=250,
        )
        return timestamps

    def has_speech(self, pcm_bytes: bytes, sample_rate: int = 16000) -> bool:
        """Check if audio contains voice activity."""
        timestamps = self.detect_speech(pcm_bytes, sample_rate=sample_rate)
        return len(timestamps) > 0

    def transcribe(self, pcm_bytes: bytes, sample_rate: int = 16000) -> Tuple[str, float, str]:
        """Transcribe raw PCM bytes and return (text, confidence, language)."""
        if not self._is_ready:
            self.initialize()

        if len(pcm_bytes) < 3200:
            return "", 0.0, "en"

        wav_io = io.BytesIO()
        with wave.open(wav_io, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_bytes)
        wav_io.seek(0)

        t0 = time.time()
        segments, info = self._whisper_model.transcribe(
            wav_io,
            beam_size=1,
            language="en",
            temperature=0.0,
            vad_filter=False,
        )

        texts = []
        confidences = []
        for s in segments:
            texts.append(s.text.strip())
            speech_prob = (1.0 - s.no_speech_prob) if s.no_speech_prob is not None else 0.9
            exp_prob = float(np.exp(s.avg_logprob)) if s.avg_logprob is not None else 0.8
            conf = min(max((speech_prob * 0.5 + exp_prob * 0.5), 0.0), 1.0)
            confidences.append(conf)

        final_text = " ".join(texts).strip()
        avg_confidence = float(np.mean(confidences)) if confidences else float(info.language_probability)
        duration_ms = (time.time() - t0) * 1000
        logger.info(
            f"Transcribed {len(pcm_bytes)} B in {duration_ms:.1f}ms: \"{final_text}\" (conf: {avg_confidence:.2f})"
        )
        return final_text, avg_confidence, info.language or "en"
