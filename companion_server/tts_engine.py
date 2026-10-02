"""Local Text-to-Speech (TTS) Engine for Solace Companion Server.

Provides a unified interface for speech synthesis with support for:
1. Kokoro-82M (Sherpa-ONNX runtime) - warm, natural soothing companion voice.
2. Piper VITS (Sherpa-ONNX runtime) - ultra-fast low-latency fallback.
3. MockTtsEngine - lightweight synthetic speech envelope for testing and offline CI.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import logging
import math
import os
from pathlib import Path
import threading
import time
from typing import Any, Dict, List, Optional

import numpy as np

logger = logging.getLogger("solace_tts")

DEFAULT_SAMPLE_RATE = 24000  # Kokoro uses 24000 Hz; Piper typically uses 22050 Hz or 16000 Hz


@dataclass
class TtsAudioResult:
    """Result of a single text-to-speech synthesis operation."""
    pcm_bytes: bytes
    sample_rate: int
    duration_sec: float
    samples: np.ndarray


class BaseTtsEngine(ABC):
    """Abstract base class for companion TTS engines."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Name of the TTS engine."""
        pass

    @property
    @abstractmethod
    def is_ready(self) -> bool:
        """True if the model weights are loaded and ready to synthesize."""
        pass

    @property
    @abstractmethod
    def default_sample_rate(self) -> int:
        """Default output sample rate in Hz."""
        pass

    @abstractmethod
    def warmup(self) -> None:
        """Perform a quick dry-run synthesis to warm up JIT, cache, and runtime."""
        pass

    @abstractmethod
    def get_available_voices(self) -> List[Dict[str, Any]]:
        """List available voices for this engine."""
        pass

    @abstractmethod
    def synthesize(
        self,
        text: str,
        voice_id: Optional[str] = None,
        speed: float = 0.96,
    ) -> TtsAudioResult:
        """Synthesize text into signed 16-bit little-endian mono PCM audio."""
        pass


class MockTtsEngine(BaseTtsEngine):
    """Generates synthetic soothing sinusoidal tone sequences with smooth envelopes.

    Used for testing, CI, and fallback when model weights have not been downloaded.
    Produces valid 24 kHz signed 16-bit PCM mono bytes with realistic speech duration.
    """

    def __init__(self, sample_rate: int = DEFAULT_SAMPLE_RATE) -> None:
        self._sample_rate = sample_rate
        self._voices = [
            {"id": "af_heart", "name": "Heart (Warm Female)", "gender": "female", "engine": "mock"},
            {"id": "af_bella", "name": "Bella (Gentle Female)", "gender": "female", "engine": "mock"},
            {"id": "am_michael", "name": "Michael (Calm Male)", "gender": "male", "engine": "mock"},
            {"id": "en_US-amy", "name": "Amy (Low Latency)", "gender": "female", "engine": "mock"},
        ]

    @property
    def name(self) -> str:
        return "mock"

    @property
    def is_ready(self) -> bool:
        return True

    @property
    def default_sample_rate(self) -> int:
        return self._sample_rate

    def warmup(self) -> None:
        self.synthesize("Warmup")

    def get_available_voices(self) -> List[Dict[str, Any]]:
        return list(self._voices)

    def synthesize(
        self,
        text: str,
        voice_id: Optional[str] = None,
        speed: float = 0.96,
    ) -> TtsAudioResult:
        clean_text = text.strip()
        if not clean_text:
            return TtsAudioResult(
                pcm_bytes=b"",
                sample_rate=self._sample_rate,
                duration_sec=0.0,
                samples=np.zeros(0, dtype=np.float32),
            )

        # Estimate duration: ~55ms per character at speed 1.0 (typical conversational tempo)
        effective_speed = max(0.5, min(2.0, speed))
        char_count = max(len(clean_text), 8)
        duration_sec = (char_count * 0.055) / effective_speed
        duration_sec = max(0.2, min(duration_sec, 8.0))

        num_samples = int(duration_sec * self._sample_rate)
        t = np.linspace(0, duration_sec, num_samples, endpoint=False, dtype=np.float32)

        # Base tone frequency depends on voice selection
        base_freq = 220.0 if (voice_id and "am_" in voice_id) else 330.0

        # Harmonically rich, warm soothing tone (fundamental + subtle 2nd & 3rd harmonic)
        wave = (
            0.35 * np.sin(2 * np.pi * base_freq * t)
            + 0.15 * np.sin(2 * np.pi * (base_freq * 1.5) * t)
            + 0.08 * np.sin(2 * np.pi * (base_freq * 2.0) * t)
        )

        # Apply gentle speech-like syllable amplitude modulation (~4 Hz cadence)
        cadence = 0.6 + 0.4 * np.sin(2 * np.pi * 4.0 * t)
        wave = wave * cadence

        # Apply attack (20ms) and release (30ms) raised-cosine fade to eliminate clicks
        fade_in_len = min(int(0.02 * self._sample_rate), num_samples // 4)
        fade_out_len = min(int(0.03 * self._sample_rate), num_samples // 4)

        if fade_in_len > 0:
            fade_in = 0.5 * (1 - np.cos(np.pi * np.arange(fade_in_len) / fade_in_len))
            wave[:fade_in_len] *= fade_in

        if fade_out_len > 0:
            fade_out = 0.5 * (1 + np.cos(np.pi * np.arange(fade_out_len) / fade_out_len))
            wave[-fade_out_len:] *= fade_out

        # Clip and convert to 16-bit signed LE PCM bytes
        wave = np.clip(wave, -1.0, 1.0)
        pcm_bytes = (wave * 32767).astype(np.int16).tobytes()

        return TtsAudioResult(
            pcm_bytes=pcm_bytes,
            sample_rate=self._sample_rate,
            duration_sec=duration_sec,
            samples=wave,
        )


class EdgeTtsEngine(BaseTtsEngine):
    """High-fidelity neural TTS engine powered by edge-tts with PyAV decoding.

    Produces natural, studio-quality human speech with warm, soothing empathy.
    Supports multiple voice personas (Ava, Jenny, Emma, Andrew, Guy, Ana).
    """

    def __init__(self, sample_rate: int = DEFAULT_SAMPLE_RATE) -> None:
        self._sample_rate = sample_rate
        self._voices = [
            {"id": "af_heart", "name": "Heart (Warm Female)", "gender": "female", "engine": "neural", "voice": "en-US-AvaNeural"},
            {"id": "af_bella", "name": "Bella (Gentle Female)", "gender": "female", "engine": "neural", "voice": "en-US-JennyNeural"},
            {"id": "af_sarah", "name": "Sarah (Calm Female)", "gender": "female", "engine": "neural", "voice": "en-US-EmmaNeural"},
            {"id": "am_michael", "name": "Michael (Calm Male)", "gender": "male", "engine": "neural", "voice": "en-US-AndrewNeural"},
            {"id": "am_adam", "name": "Adam (Gentle Male)", "gender": "male", "engine": "neural", "voice": "en-US-GuyNeural"},
            {"id": "en_US-amy", "name": "Amy (Soft Female)", "gender": "female", "engine": "neural", "voice": "en-US-AnaNeural"},
        ]
        self._voice_map = {v["id"]: v["voice"] for v in self._voices}
        self._fallback_mock = MockTtsEngine(sample_rate=sample_rate)

    @property
    def name(self) -> str:
        return "neural"

    @property
    def is_ready(self) -> bool:
        return True

    @property
    def default_sample_rate(self) -> int:
        return self._sample_rate

    def warmup(self) -> None:
        try:
            self.synthesize("Warmup.")
        except Exception as e:
            logger.debug(f"EdgeTts warmup notice: {e}")

    def get_available_voices(self) -> List[Dict[str, Any]]:
        return list(self._voices)

    def synthesize(
        self,
        text: str,
        voice_id: Optional[str] = None,
        speed: float = 0.96,
    ) -> TtsAudioResult:
        clean_text = text.strip()
        if not clean_text:
            return TtsAudioResult(
                pcm_bytes=b"",
                sample_rate=self._sample_rate,
                duration_sec=0.0,
                samples=np.zeros(0, dtype=np.float32),
            )

        neural_voice = self._voice_map.get(voice_id or "af_heart", "en-US-AvaNeural")
        rate_str = f"{int((speed - 1.0) * 100):+d}%"

        try:
            import asyncio
            import io
            import av
            import edge_tts

            async def _run():
                comm = edge_tts.Communicate(clean_text, neural_voice, rate=rate_str)
                mp3_buf = bytearray()
                async for chunk in comm.stream():
                    if chunk["type"] == "audio":
                        mp3_buf.extend(chunk["data"])
                return bytes(mp3_buf)

            mp3_data = asyncio.run(_run())

            if not mp3_data:
                return self._fallback_mock.synthesize(clean_text, voice_id=voice_id, speed=speed)

            # Decode MP3 to 24000Hz 16-bit mono PCM via PyAV
            container = av.open(io.BytesIO(mp3_data))
            stream = container.streams.audio[0]
            resampler = av.AudioResampler(format="s16", layout="mono", rate=self._sample_rate)

            pcm_chunks = []
            for frame in container.decode(stream):
                for rf in resampler.resample(frame):
                    pcm_chunks.append(rf.to_ndarray().tobytes())

            pcm_bytes = b"".join(pcm_chunks)
            samples = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
            duration_sec = len(samples) / self._sample_rate

            return TtsAudioResult(
                pcm_bytes=pcm_bytes,
                sample_rate=self._sample_rate,
                duration_sec=duration_sec,
                samples=samples,
            )

        except Exception as e:
            logger.warning(f"EdgeTts synthesis error ({e}), falling back to mock: {e}")
            return self._fallback_mock.synthesize(clean_text, voice_id=voice_id, speed=speed)


class SherpaOnnxTtsEngine(BaseTtsEngine):
    """High-performance on-device TTS using sherpa-onnx (Kokoro-82M or Piper VITS)."""

    def __init__(
        self,
        model_path: str | Path,
        tokens_path: str | Path,
        voices_path: Optional[str | Path] = None,
        data_dir: Optional[str | Path] = None,
        is_kokoro: bool = True,
        num_threads: int = 2,
    ) -> None:
        self.model_path = Path(model_path)
        self.tokens_path = Path(tokens_path)
        self.voices_path = Path(voices_path) if voices_path else None
        self.data_dir = Path(data_dir) if data_dir else None
        self.is_kokoro = is_kokoro
        self.num_threads = num_threads

        self._tts: Any = None
        self._sample_rate: int = DEFAULT_SAMPLE_RATE
        self._lock = threading.Lock()
        self._is_ready: bool = False

        # Predefined voice names supported by Kokoro-82M
        self._kokoro_voices = [
            {"id": "af_heart", "sid": 0, "name": "Heart (Warm Female)", "gender": "female"},
            {"id": "af_bella", "sid": 1, "name": "Bella (Gentle Female)", "gender": "female"},
            {"id": "af_sarah", "sid": 2, "name": "Sarah (Calm Female)", "gender": "female"},
            {"id": "am_michael", "sid": 3, "name": "Michael (Calm Male)", "gender": "male"},
            {"id": "am_adam", "sid": 4, "name": "Adam (Gentle Male)", "gender": "male"},
        ]

    @property
    def name(self) -> str:
        return "kokoro" if self.is_kokoro else "piper"

    @property
    def is_ready(self) -> bool:
        return self._is_ready

    @property
    def default_sample_rate(self) -> int:
        return self._sample_rate

    def initialize(self) -> bool:
        """Initialize and load the sherpa-onnx OfflineTts model."""
        with self._lock:
            if self._is_ready:
                return True

            try:
                import sherpa_onnx

                if not self.model_path.exists():
                    logger.warning(f"TTS model weights not found at: {self.model_path}")
                    return False

                if self.is_kokoro:
                    kokoro_config = sherpa_onnx.OfflineTtsKokoroModelConfig(
                        model=str(self.model_path),
                        voices=str(self.voices_path) if self.voices_path else "",
                        tokens=str(self.tokens_path),
                        data_dir=str(self.data_dir) if self.data_dir else "",
                    )
                    model_config = sherpa_onnx.OfflineTtsModelConfig(
                        kokoro=kokoro_config,
                        num_threads=self.num_threads,
                        provider="cpu",
                    )
                else:
                    if not self.data_dir or not self.data_dir.exists():
                        logger.warning("Piper TTS requires valid espeak-ng-data directory.")
                        return False
                    vits_config = sherpa_onnx.OfflineTtsVitsModelConfig(
                        model=str(self.model_path),
                        tokens=str(self.tokens_path),
                        data_dir=str(self.data_dir),
                    )
                    model_config = sherpa_onnx.OfflineTtsModelConfig(
                        vits=vits_config,
                        num_threads=self.num_threads,
                        provider="cpu",
                    )

                tts_config = sherpa_onnx.OfflineTtsConfig(model=model_config)
                self._tts = sherpa_onnx.OfflineTts(tts_config)
                self._sample_rate = self._tts.sample_rate
                self._is_ready = True
                logger.info(
                    f"SherpaOnnxTtsEngine ({self.name}) initialized successfully! "
                    f"Sample rate: {self._sample_rate} Hz, threads: {self.num_threads}"
                )
                return True
            except Exception as e:
                logger.error(f"Failed to initialize SherpaOnnxTtsEngine: {e}", exc_info=True)
                self._is_ready = False
                return False

    def warmup(self) -> None:
        if not self._is_ready:
            self.initialize()
        if self._is_ready:
            t0 = time.time()
            self.synthesize("Hello")
            logger.info(f"TTS engine warmup completed in {time.time() - t0:.3f}s")

    def get_available_voices(self) -> List[Dict[str, Any]]:
        if self.is_kokoro:
            return list(self._kokoro_voices)
        return [{"id": "default", "sid": 0, "name": "Default Piper Voice", "gender": "neutral"}]

    def synthesize(
        self,
        text: str,
        voice_id: Optional[str] = None,
        speed: float = 0.96,
    ) -> TtsAudioResult:
        if not self._is_ready:
            self.initialize()

        if not self._is_ready or self._tts is None:
            raise RuntimeError("SherpaOnnxTtsEngine is not initialized")

        clean_text = text.strip()
        if not clean_text:
            return TtsAudioResult(
                pcm_bytes=b"",
                sample_rate=self._sample_rate,
                duration_sec=0.0,
                samples=np.zeros(0, dtype=np.float32),
            )

        # Resolve speaker sid
        sid = 0
        if self.is_kokoro and voice_id:
            for v in self._kokoro_voices:
                if v["id"] == voice_id:
                    sid = v["sid"]
                    break

        # One decode at a time: the runtime session is not re-entrant, and the
        # reply pipeline now prefetches the next clause while one is in flight.
        with self._lock:
            audio = self._tts.generate(clean_text, sid=sid, speed=speed)
        samples = np.array(audio.samples, dtype=np.float32)
        sample_rate = audio.sample_rate

        # Fade in/out by 25ms to prevent pops
        num_samples = len(samples)
        fade_len = min(int(0.025 * sample_rate), num_samples // 4)
        if fade_len > 0:
            fade_in = 0.5 * (1 - np.cos(np.pi * np.arange(fade_len) / fade_len))
            fade_out = 0.5 * (1 + np.cos(np.pi * np.arange(fade_len) / fade_len))
            samples[:fade_len] *= fade_in
            samples[-fade_len:] *= fade_out

        samples = np.clip(samples, -1.0, 1.0)
        pcm_bytes = (samples * 32767).astype(np.int16).tobytes()
        duration_sec = len(samples) / sample_rate

        return TtsAudioResult(
            pcm_bytes=pcm_bytes,
            sample_rate=sample_rate,
            duration_sec=duration_sec,
            samples=samples,
        )


def get_tts_engine(
    engine_type: str = "auto",
    models_dir: Optional[str | Path] = None,
) -> BaseTtsEngine:
    """Factory to acquire the best available TTS engine.

    `engine_type` comes from SOLACE_TTS: auto | kokoro | piper | edge | mock.

    Priority for `auto`:
    1. Local Kokoro / Piper ONNX weights, when the model files are present
    2. EdgeTtsEngine -> cloud neural voices (needs internet; ~1.5 s per clause)
    3. Fallback -> MockTtsEngine

    `piper` and `kokoro` force the local engine; if its files are incomplete the
    factory says what is missing rather than silently using the cloud voice.
    """
    if engine_type == "mock":
        return MockTtsEngine()

    # `edge` skips local weights entirely: the cloud voice, chosen explicitly.
    if engine_type == "edge":
        return EdgeTtsEngine()

    base_dir = Path(models_dir) if models_dir else Path(__file__).resolve().parent / "models" / "tts"

    # Check for Kokoro ONNX model
    kokoro_model = base_dir / "kokoro-v0_19.onnx"
    kokoro_tokens = base_dir / "tokens.txt"
    kokoro_voices = base_dir / "voices.bin"
    # espeak-ng-data may live next to the models or wherever SOLACE_ESPEAK_DATA says.
    kokoro_data = Path(os.environ.get("SOLACE_ESPEAK_DATA", base_dir / "espeak-ng-data"))

    if engine_type in ("auto", "kokoro") and kokoro_model.exists() and kokoro_tokens.exists():
        engine = SherpaOnnxTtsEngine(
            model_path=kokoro_model,
            tokens_path=kokoro_tokens,
            voices_path=kokoro_voices if kokoro_voices.exists() else None,
            data_dir=kokoro_data if kokoro_data.exists() else None,
            is_kokoro=True,
        )
        if engine.initialize():
            return engine

    # Check for Piper VITS model
    piper_model = base_dir / "en_US-amy-low.onnx"
    piper_tokens = base_dir / "tokens.txt"
    piper_data = kokoro_data

    if engine_type == "piper" and not piper_data.exists():
        logger.warning(
            f"SOLACE_TTS=piper but espeak-ng-data was not found at {piper_data}; "
            "set SOLACE_ESPEAK_DATA or copy the folder next to the model."
        )
    if (
        engine_type in ("auto", "piper")
        and piper_model.exists() and piper_tokens.exists() and piper_data.exists()
    ):
        engine = SherpaOnnxTtsEngine(
            model_path=piper_model,
            tokens_path=piper_tokens,
            data_dir=piper_data,
            is_kokoro=False,
        )
        if engine.initialize():
            return engine

    # High-fidelity Neural Edge-TTS (cloud)
    if engine_type in ("auto", "neural", "edge"):
        try:
            import edge_tts
            import av
            return EdgeTtsEngine()
        except ImportError:
            pass

    # If no local model weights found, use MockTtsEngine
    logger.info(
        f"No local TTS ONNX weights found in '{base_dir}'. Using high-fidelity MockTtsEngine fallback."
    )
    return MockTtsEngine()
