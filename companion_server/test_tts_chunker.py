"""Unit tests for TextChunker and TtsEngine in Solace Companion Backend."""

import asyncio
import pytest
import numpy as np

from text_chunker import TextChunker, normalize_text_for_voice
from tts_engine import MockTtsEngine, get_tts_engine, TtsAudioResult


def test_normalize_text_for_voice():
    raw = (
        "**Solace:** I hear you. Take a *deep* breath 🌸 and ~~rush~~ relax. "
        "Visit [crisis resources](https://988lifeline.org) if needed. `code`"
    )
    normalized = normalize_text_for_voice(raw)
    assert "**" not in normalized
    assert "*" not in normalized
    assert "~~" not in normalized
    assert "🌸" not in normalized
    assert "[" not in normalized
    assert "https://" not in normalized
    assert "`" not in normalized
    assert "Solace: I hear you. Take a deep breath and relax. Visit crisis resources if needed. code" in normalized


def test_text_chunker_sentence_splitting():
    chunker = TextChunker(min_chunk_chars=15, normal_chunk_chars=60)
    tokens = [
        "I ", "hear ", "you. ", "That ", "sounds ", "really ", "heavy ",
        "right ", "now. ", "Please ", "take ", "your ", "time."
    ]

    emitted = []
    for token in tokens:
        chunks = chunker.add_token(token)
        emitted.extend(chunks)

    final = chunker.flush()
    if final:
        emitted.append(final)

    assert len(emitted) >= 2
    assert "I hear you." in emitted[0]
    assert any("really heavy right now." in c for c in emitted)


def test_text_chunker_abbreviation_preservation():
    chunker = TextChunker(min_chunk_chars=10, normal_chunk_chars=80)
    # Feeding a sentence with Dr. and Mrs.
    text = "Dr. Smith and Mrs. Taylor are here to help you today. Please breathe."
    chunks = chunker.add_token(text)
    final = chunker.flush()
    if final:
        chunks.append(final)

    # Should NOT have split at "Dr." or "Mrs."
    assert not any(c.strip() == "Dr." for c in chunks)
    assert not any(c.strip() == "Mrs." for c in chunks)
    assert any("Dr. Smith and Mrs. Taylor are here to help you today." in c for c in chunks)


def test_text_chunker_decimal_preservation():
    chunker = TextChunker(min_chunk_chars=10, normal_chunk_chars=80)
    text = "Your average rating is 4.8 out of 5.0 points. That is wonderful."
    chunks = chunker.add_token(text)
    final = chunker.flush()
    if final:
        chunks.append(final)

    # Should not split at 4. or 5.
    assert not any(c.strip() == "Your average rating is 4." for c in chunks)
    assert any("4.8 out of 5.0 points." in c for c in chunks)


def test_text_chunker_max_chars_force_split():
    chunker = TextChunker(min_chunk_chars=20, max_chars=50)
    long_sentence = (
        "This is an unusually long run on sentence without any punctuation whatsoever "
        "so the chunker must split it at a word boundary to prevent delay"
    )
    chunks = []
    for word in long_sentence.split(" "):
        chunks.extend(chunker.add_token(word + " "))
    final = chunker.flush()
    if final:
        chunks.append(final)

    # Every chunk should be under or equal to max_chars (or word boundary)
    assert len(chunks) >= 2
    for chunk in chunks:
        assert len(chunk) <= 65


def test_text_chunker_flush():
    chunker = TextChunker(min_chunk_chars=30)
    chunker.add_token("I am here with you")
    assert chunker.buffer == "I am here with you"

    flushed = chunker.flush()
    assert flushed == "I am here with you"
    assert chunker.buffer == ""


@pytest.mark.asyncio
async def test_text_chunker_stream_chunks_async():
    chunker = TextChunker(min_chunk_chars=15, normal_chunk_chars=50)

    async def sample_token_stream():
        tokens = ["I ", "am ", "listening. ", "Tell ", "me ", "more ", "about ", "it. "]
        for t in tokens:
            await asyncio.sleep(0.01)
            yield t

    chunks = []
    async for chunk in chunker.stream_chunks(sample_token_stream(), flush_timeout_sec=0.2):
        chunks.append(chunk)

    assert len(chunks) >= 2
    assert "I am listening." in chunks[0]
    assert "Tell me more about it." in chunks[1]


def test_mock_tts_engine():
    engine = MockTtsEngine(sample_rate=24000)
    assert engine.name == "mock"
    assert engine.is_ready is True
    assert engine.default_sample_rate == 24000

    voices = engine.get_available_voices()
    assert len(voices) >= 2
    voice_ids = [v["id"] for v in voices]
    assert "af_heart" in voice_ids

    # Synthesize phrase
    result = engine.synthesize("Take a deep, gentle breath.", voice_id="af_heart", speed=0.96)
    assert isinstance(result, TtsAudioResult)
    assert len(result.pcm_bytes) > 0
    # 16-bit PCM = 2 bytes per sample
    assert len(result.pcm_bytes) % 2 == 0
    assert result.sample_rate == 24000
    assert result.duration_sec > 0.3
    assert len(result.samples) > 0

    # Ensure audio values are within 16-bit signed range
    audio_int16 = np.frombuffer(result.pcm_bytes, dtype=np.int16)
    assert np.all(audio_int16 >= -32768)
    assert np.all(audio_int16 <= 32767)


def test_get_tts_engine_factory():
    # Test explicit mock
    engine = get_tts_engine(engine_type="mock")
    assert isinstance(engine, MockTtsEngine)

    # Test auto fallback when no models are downloaded yet
    auto_engine = get_tts_engine(engine_type="auto")
    assert auto_engine.is_ready is True
    assert auto_engine.default_sample_rate in (24000, 22050, 16000)
