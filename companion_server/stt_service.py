import asyncio
import io
import logging
import threading
import time
from typing import Dict, List, Optional, Tuple
import wave

import numpy as np
import torch
from faster_whisper import WhisperModel
from silero_vad import load_silero_vad, get_speech_timestamps, get_speech_timestamps_from_probs

logger = logging.getLogger("solace_companion.stt")

# Silero is called 50x/second on a 512-sample window. Extra torch threads only
# add contention with Whisper's cpu_threads=4 on the same box.
torch.set_num_threads(1)

# Silero v5/v6 internal geometry.
VAD_WINDOW = 512          # samples per inference step (32 ms @ 16 kHz)
VAD_CONTEXT = 64          # samples of leading context the model keeps itself

# The model is stateful (LSTM + context) and shared by every session, by the
# streaming path and by the batch path. `get_speech_timestamps` calls
# reset_states() internally, so an unguarded batch pass silently wipes a
# concurrent streaming turn's state and that turn looks like near-silence.
_VAD_LOCK = threading.Lock()


class StreamingVad:
    """Frame-at-a-time Silero wrapper.

    The batch API (`get_speech_timestamps` over a whole buffer) structurally
    cannot emit a speech-onset event before the buffer is closed, which is why
    barge-in used to wait for a full transcription. This keeps the model's
    internal state (512-sample window + 64-sample context + LSTM) between calls
    so a crossing can be reported in ~32 ms of server time.
    """

    def __init__(self, model, sample_rate: int = 16000, threshold: float = 0.5,
                 neg_threshold: float = 0.35):
        self._model = model
        self._sample_rate = sample_rate
        self.threshold = threshold
        self.neg_threshold = neg_threshold
        self.reset()

    def reset(self) -> None:
        """Call on turn start so no probability leaks across turns."""
        with _VAD_LOCK:
            try:
                self._model.reset_states()
            except Exception:  # pragma: no cover - older silero builds
                pass
        # The model keeps its own 64-sample context between calls; it wants
        # exactly one 512-sample window per inference.
        self._buffer = np.zeros(VAD_WINDOW, dtype=np.float32)
        self._filled = 0
        self.speech_samples = 0
        self.silence_samples = 0
        self.ever_spoke = False
        self.speech_start_sample = -1
        self.last_speech_sample = -1
        self.total_samples = 0
        self.peak_prob = 0.0
        self._probs: List[float] = []

    @property
    def speech_ms(self) -> int:
        return int(self.speech_samples / self._sample_rate * 1000)

    @property
    def probabilities(self) -> List[float]:
        return list(self._probs)

    def push(self, pcm_bytes: bytes) -> float:
        """Feed pcm16 bytes, return the probability for the last completed window."""
        if not pcm_bytes:
            return 0.0
        samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        self.total_samples += len(samples)
        offset = 0
        prob = 0.0
        while offset < len(samples):
            take = min(VAD_WINDOW - self._filled, len(samples) - offset)
            self._buffer[self._filled:self._filled + take] = samples[offset:offset + take]
            self._filled += take
            offset += take
            if self._filled < VAD_WINDOW:
                break
            with _VAD_LOCK:
                prob = float(self._model(torch.from_numpy(self._buffer), self._sample_rate).item())
            self._filled = 0
            self._record(prob)
        return prob

    def _record(self, prob: float) -> None:
        self._probs.append(prob)
        self.peak_prob = max(self.peak_prob, prob)
        if prob >= self.threshold:
            if not self.ever_spoke:
                self.ever_spoke = True
                self.speech_start_sample = max(0, self.total_samples - VAD_WINDOW)
            self.speech_samples += VAD_WINDOW
            self.silence_samples = 0
            self.last_speech_sample = self.total_samples
        elif prob < self.neg_threshold:
            if self.ever_spoke:
                self.silence_samples += VAD_WINDOW
        # Between the thresholds is the ambiguity band: neither confirm nor deny.


class SttService:
    def __init__(self, model_size: str = "base.en"):
        self.model_size = model_size
        self._vad_model = None
        self._whisper_model = None
        self._device = "cpu"
        self._compute_type = "int8"
        self._is_ready = False
        # Session-configurable (§5.11). Server config wins over the client.
        self.vad_threshold = 0.5
        self.vad_neg_threshold = 0.35
        self.vad_min_speech_ms = 120

    def initialize(self):
        """Pre-load Silero VAD and Whisper model."""
        if self._is_ready:
            return

        logger.info("Initializing Silero VAD...")
        t0 = time.time()
        # onnx=True is ~4.4x cheaper per frame than the TorchScript build.
        self._vad_model = load_silero_vad(onnx=True)
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

    def new_streaming_vad(self, sample_rate: int = 16000) -> StreamingVad:
        if not self._is_ready:
            self.initialize()
        return StreamingVad(
            self._vad_model,
            sample_rate=sample_rate,
            threshold=self.vad_threshold,
            neg_threshold=self.vad_neg_threshold,
        )

    def detect_speech(self, pcm_bytes: bytes, sample_rate: int = 16000) -> List[Dict[str, int]]:
        """Return list of speech timestamps {'start': int, 'end': int} using Silero VAD."""
        if not self._is_ready:
            self.initialize()

        if len(pcm_bytes) < 3200:  # less than 100ms
            return []

        audio_np = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        wav_tensor = torch.from_numpy(audio_np)
        with _VAD_LOCK:
            timestamps = get_speech_timestamps(
                wav_tensor,
                self._vad_model,
                sampling_rate=sample_rate,
                threshold=self.vad_threshold,
                min_speech_duration_ms=self.vad_min_speech_ms,
                # No min_silence_duration_ms: the turn-end deadline belongs to the
                # endpointing policy (§5.7), not to a batch post-process.
                min_silence_duration_ms=0,
            )
        return timestamps

    def has_speech(self, pcm_bytes: bytes, sample_rate: int = 16000) -> bool:
        """Check if audio contains voice activity."""
        timestamps = self.detect_speech(pcm_bytes, sample_rate=sample_rate)
        return len(timestamps) > 0

    def transcribe(self, pcm_bytes: bytes, sample_rate: int = 16000) -> Tuple[str, float, str]:
        """Transcribe raw PCM bytes and return (text, confidence, language)."""
        return self.analyze(pcm_bytes, sample_rate=sample_rate)[:3]

    def analyze(self, pcm_bytes: bytes, sample_rate: int = 16000,
                probabilities: Optional[List[float]] = None) -> Tuple[str, float, str, float, int]:
        """One pass over a turn: VAD decision, transcript and confidence.

        Returns (text, confidence, language, eot_probability, speech_ms).
        `probabilities` may be the vector already produced by [StreamingVad]
        during capture; when supplied, the VAD model is not run a second time.
        """
        if not self._is_ready:
            self.initialize()

        if len(pcm_bytes) < 3200:
            return "", 0.0, "en", 0.0, 0

        t0 = time.time()

        # 1. Speech decision. The streaming vector is reused when available.
        speech_ms = 0
        step_ms = VAD_WINDOW / sample_rate * 1000
        if probabilities:
            with _VAD_LOCK:
                timestamps = get_speech_timestamps_from_probs(
                    list(probabilities),
                    sampling_rate=sample_rate,
                    threshold=self.vad_threshold,
                    neg_threshold=self.vad_neg_threshold,
                    min_speech_duration_ms=self.vad_min_speech_ms,
                )
            speech_ms = int(sum(t["end"] - t["start"] for t in timestamps) * step_ms)
        else:
            timestamps = self.detect_speech(pcm_bytes, sample_rate=sample_rate)
            speech_ms = int(
                sum(t["end"] - t["start"] for t in timestamps) * 1000 / sample_rate
            )

        if not timestamps:
            logger.info(f"No speech in {len(pcm_bytes)} B (vad {time.time() - t0:.3f}s)")
            return "", 0.0, "en", 0.0, 0

        # 2. End-of-turn probability: mean of the final 300 ms of probabilities.
        # Phase 3 replaces this with a semantic model; it is telemetry for now.
        eot_probability = float(np.mean(probabilities[-15:])) if probabilities else 0.0

        wav_io = io.BytesIO()
        with wave.open(wav_io, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_bytes)
        wav_io.seek(0)

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
            f"Transcribed {len(pcm_bytes)} B in {duration_ms:.1f}ms: \"{final_text}\" "
            f"(conf: {avg_confidence:.2f}, speech: {speech_ms}ms)"
        )
        return final_text, avg_confidence, info.language or "en", eot_probability, speech_ms
