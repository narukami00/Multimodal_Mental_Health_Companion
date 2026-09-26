"""Text Chunker for Solace LLM-to-TTS Pipeline.

Buffers streaming LLM tokens, detects sentence and clause boundaries, normalizes
text (stripping markdown, vocalized emojis), and emits speakable text chunks with
low time-to-first-audio (TTFA) and natural conversational cadence.
"""

from __future__ import annotations

import asyncio
import re
import time
from typing import AsyncGenerator, Iterator, List, Optional


# Regex to strip markdown formatting
_MD_BOLD_ITALIC = re.compile(r"(\*{1,3}|_{1,3})(.*?)\1")
_MD_STRIKE = re.compile(r"~~(.*?)~~")
_MD_LINKS = re.compile(r"\[(.*?)\]\([^)]+\)")
_MD_HEADERS = re.compile(r"^\s*#{1,6}\s+", re.MULTILINE)
_MD_CODE_BLOCKS = re.compile(r"```[\s\S]*?```")
_MD_INLINE_CODE = re.compile(r"`([^`]+)`")

# Regex to strip emojis and non-standard symbols for TTS
_EMOJI_PATTERN = re.compile(
    r"[\U00010000-\U0010ffff"  # Supplemental symbols / emojis
    r"\u2600-\u27bf"           # Misc symbols, dingbats
    r"\ufe00-\ufe0f"           # Variation selectors
    r"\u200d"                  # Zero-width joiner
    r"]+",
    flags=re.UNICODE,
)

# Common abbreviations that should NOT end a sentence
_ABBREVIATIONS = {
    "mr", "mrs", "ms", "dr", "prof", "sr", "jr",
    "vs", "etc", "eg", "ie", "approx", "dept", "est",
}

# Strong sentence boundaries: . ! ? … \n
_STRONG_ENDINGS = {".", "!", "?", "…", "\n"}
# Weak clause boundaries: , ; : — -
_WEAK_ENDINGS = {",", ";", ":", "—", "-"}


def normalize_text_for_voice(text: str) -> str:
    """Clean and normalize raw LLM text for speech synthesis.

    Strips markdown formatting, URLs, emojis, and extraneous whitespace.
    """
    if not text:
        return ""

    # Strip code blocks and inline code
    cleaned = _MD_CODE_BLOCKS.sub("", text)
    cleaned = _MD_INLINE_CODE.sub(r"\1", cleaned)

    # Strip links and markdown headers
    cleaned = _MD_LINKS.sub(r"\1", cleaned)
    cleaned = _MD_HEADERS.sub("", cleaned)

    # Strip bold / italic
    cleaned = _MD_BOLD_ITALIC.sub(r"\2", cleaned)
    # Strip strikethrough completely
    cleaned = _MD_STRIKE.sub("", cleaned)

    # Strip emojis
    cleaned = _EMOJI_PATTERN.sub(" ", cleaned)

    # Replace multiple spaces with a single space
    cleaned = re.sub(r"[ \t]+", " ", cleaned)
    # Normalize multiple newlines
    cleaned = re.sub(r"\n{2,}", "\n", cleaned)

    return cleaned.strip()


class TextChunker:
    """Accumulates streaming tokens and emits speakable sentence/clause units."""

    def __init__(
        self,
        min_chunk_chars: int = 30,
        normal_chunk_chars: int = 110,
        comma_min_chars: int = 85,
        max_chars: int = 200,
        is_call_mode: bool = False,
    ) -> None:
        """Initialize chunker with mode-specific thresholds.

        In call mode, thresholds are reduced to prioritize rapid turn latency.
        """
        if is_call_mode:
            self.min_chunk_chars = 20
            self.normal_chunk_chars = 80
            self.comma_min_chars = 60
            self.max_chars = 150
        else:
            self.min_chunk_chars = min_chunk_chars
            self.normal_chunk_chars = normal_chunk_chars
            self.comma_min_chars = comma_min_chars
            self.max_chars = max_chars

        self._buffer: str = ""
        self._is_first_chunk: bool = True
        self._last_token_time: float = time.monotonic()

    @property
    def buffer(self) -> str:
        return self._buffer

    def reset(self) -> None:
        """Clear buffer and reset chunk state."""
        self._buffer = ""
        self._is_first_chunk = True
        self._last_token_time = time.monotonic()

    def add_token(self, token: str) -> List[str]:
        """Add a token to buffer and return any complete speakable chunks."""
        if not token:
            return []

        self._buffer += token
        self._last_token_time = time.monotonic()
        emitted: List[str] = []

        while self._buffer:
            chunk = self._extract_next_chunk()
            if chunk:
                cleaned = normalize_text_for_voice(chunk)
                if cleaned:
                    emitted.append(cleaned)
                    self._is_first_chunk = False
            else:
                break

        return emitted

    def flush(self) -> Optional[str]:
        """Flush any remaining buffered text at end of stream."""
        if not self._buffer.strip():
            self._buffer = ""
            return None

        remaining = normalize_text_for_voice(self._buffer)
        self.reset()
        return remaining if remaining else None

    def _extract_next_chunk(self) -> Optional[str]:
        """Find the earliest valid boundary to slice a chunk from self._buffer."""
        text = self._buffer
        n = len(text)
        if n == 0:
            return None

        # Effective minimum character threshold
        min_len = (self.min_chunk_chars // 2) if self._is_first_chunk else self.min_chunk_chars

        # Check for forced word-boundary split if buffer exceeds max_chars
        if n >= self.max_chars:
            # Find the last space before max_chars
            cut_idx = text.rfind(" ", 0, self.max_chars)
            if cut_idx > min_len:
                chunk = text[:cut_idx].strip()
                self._buffer = text[cut_idx:].lstrip()
                return chunk
            # If no space found, force cut at max_chars
            chunk = text[: self.max_chars].strip()
            self._buffer = text[self.max_chars :].lstrip()
            return chunk

        # Look for sentence or clause boundaries
        for idx in range(min_len, n):
            char = text[idx]

            # 1. Strong punctuation: . ! ? … \n
            if char in _STRONG_ENDINGS:
                # Check for decimal numbers (e.g., 3.14)
                if char == "." and idx > 0 and idx + 1 < n:
                    if text[idx - 1].isdigit() and text[idx + 1].isdigit():
                        continue

                # Check for abbreviations (e.g., Dr., Mr., vs.)
                if char == "." and idx > 1:
                    prev_word = re.findall(r"[A-Za-z]+", text[:idx])
                    if prev_word and prev_word[-1].lower() in _ABBREVIATIONS:
                        continue

                # Check for trailing quotes or brackets after punctuation (e.g., ." or ?')
                end_idx = idx + 1
                while end_idx < n and text[end_idx] in {"\"", "'", ")", "]", "”", "’"}:
                    end_idx += 1

                chunk = text[:end_idx].strip()
                self._buffer = text[end_idx:].lstrip()
                return chunk

            # 2. Weak punctuation (comma, semicolon, dash): only if buffer >= comma_min_chars
            if char in _WEAK_ENDINGS and idx >= self.comma_min_chars:
                # Don't split inside a word like hyphenated-word if followed immediately by letter
                if char == "-" and idx + 1 < n and text[idx + 1].isalpha():
                    continue

                end_idx = idx + 1
                while end_idx < n and text[end_idx] in {"\"", "'", ")", "]", "”", "’"}:
                    end_idx += 1

                chunk = text[:end_idx].strip()
                self._buffer = text[end_idx:].lstrip()
                return chunk

        return None

    async def stream_chunks(
        self,
        token_stream: AsyncGenerator[str, None],
        flush_timeout_sec: float = 0.4,
    ) -> AsyncGenerator[str, None]:
        """Convert an async stream of tokens into an async stream of speakable chunks.

        Includes a timeout flush: if no new token arrives within flush_timeout_sec
        and the buffer contains a speakable clause (>= min_chunk_chars), it flushes early.
        """
        self.reset()
        done = False
        stream_iter = token_stream.__aiter__()

        while not done:
            try:
                # Wait for next token or timeout
                token = await asyncio.wait_for(stream_iter.__anext__(), timeout=flush_timeout_sec)
                for chunk in self.add_token(token):
                    yield chunk
            except asyncio.TimeoutError:
                # Flush buffer if speakable
                if len(self._buffer.strip()) >= self.min_chunk_chars:
                    chunk = self._extract_next_chunk()
                    if chunk:
                        cleaned = normalize_text_for_voice(chunk)
                        if cleaned:
                            yield cleaned
                            self._is_first_chunk = False
            except StopAsyncIteration:
                done = True

        # End of stream flush
        final_chunk = self.flush()
        if final_chunk:
            yield final_chunk
