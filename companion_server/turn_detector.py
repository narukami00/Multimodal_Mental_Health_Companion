"""Server-side turn detection: speech onset and end-of-turn from Silero probabilities.

The phone streams the microphone continuously; the server alone decides when a
person started and stopped speaking. A neural VAD separates speech from room
noise at the low signal-to-noise ratios a phone mic produces on a desk, which a
volume threshold cannot.

The detector is pure: it consumes one speech probability per VAD window and
returns events. It owns no audio, no clock and no I/O, so every behaviour here
is unit-testable with synthetic probability sequences.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

# One Silero window: 512 samples @ 16 kHz.
WINDOW_MS = 32


@dataclass(frozen=True)
class TurnEvent:
    """One transition reported by [TurnDetector.push]."""

    kind: str  # "speech_start" | "speech_end" | "discard"
    # Window index (0-based, since reset) the event refers to. For speech_start
    # this is the first window of the confirmed run, i.e. where the audio of the
    # turn begins; for speech_end it is the last window that held speech.
    window: int
    speech_ms: int = 0
    silence_ms: int = 0
    reason: str = ""


class TurnDetector:
    """Speech onset / endpoint state machine over per-window probabilities.

    Onset needs [min_speech_ms] of consecutive speech windows, so a click or a
    cough never opens a turn. The end of a turn is [endpoint_ms] of continuous
    non-speech after the last speech window. A hard cap closes a turn that never
    goes quiet, so nothing can block the conversation indefinitely.
    """

    def __init__(
        self,
        threshold: float = 0.5,
        neg_threshold: float = 0.35,
        min_speech_ms: int = 128,
        endpoint_ms: int = 650,
        min_turn_speech_ms: int = 250,
        max_turn_ms: int = 30000,
    ) -> None:
        self.threshold = threshold
        self.neg_threshold = neg_threshold
        self.min_speech_ms = max(WINDOW_MS, int(min_speech_ms))
        self.endpoint_ms = max(WINDOW_MS, int(endpoint_ms))
        self.min_turn_speech_ms = int(min_turn_speech_ms)
        self.max_turn_ms = int(max_turn_ms)
        self.reset()

    def reset(self, keep_clock: bool = False) -> None:
        """Forget the open turn and every counter.

        [keep_clock] leaves the window numbering untouched, for a reset in the
        middle of a stream whose VAD keeps running: window indexes stay aligned
        with the audio the caller has been counting.
        """
        if not keep_clock:
            self._window = -1
        self._in_turn = False
        self._run = 0  # consecutive speech windows while idle
        self._turn_start_window = -1
        self._speech_windows = 0
        self._silence_windows = 0
        self._last_speech_window = -1

    @property
    def in_turn(self) -> bool:
        return self._in_turn

    @property
    def speech_ms(self) -> int:
        return self._speech_windows * WINDOW_MS

    @property
    def silence_ms(self) -> int:
        return self._silence_windows * WINDOW_MS

    @property
    def turn_ms(self) -> int:
        if not self._in_turn:
            return 0
        return (self._window - self._turn_start_window + 1) * WINDOW_MS

    def force_end(self, reason: str = "forced") -> Optional[TurnEvent]:
        """Close the open turn now (client asked, call ending, cap reached)."""
        if not self._in_turn:
            return None
        return self._finish(reason)

    def push(self, prob: float) -> List[TurnEvent]:
        """Feed the probability of the next window; return any events it causes."""
        self._window += 1
        events: List[TurnEvent] = []
        is_speech = prob >= self.threshold

        if not self._in_turn:
            if is_speech:
                self._run += 1
            elif prob < self.neg_threshold:
                # Only a clearly-silent window resets the run, so one wobbling
                # window inside the first syllable does not lose the onset.
                self._run = 0
            if self._run * WINDOW_MS >= self.min_speech_ms:
                self._in_turn = True
                self._turn_start_window = self._window - self._run + 1
                self._speech_windows = self._run
                self._silence_windows = 0
                self._last_speech_window = self._window
                self._run = 0
                events.append(
                    TurnEvent("speech_start", window=self._turn_start_window,
                              speech_ms=self.speech_ms)
                )
            return events

        if is_speech:
            self._speech_windows += 1
            self._silence_windows = 0
            self._last_speech_window = self._window
        else:
            self._silence_windows += 1

        if self.silence_ms >= self.endpoint_ms:
            events.append(self._finish("silence"))
        elif self.turn_ms >= self.max_turn_ms:
            events.append(self._finish("max_duration"))
        return events

    def _finish(self, reason: str) -> TurnEvent:
        speech_ms = self.speech_ms
        silence_ms = self.silence_ms
        last = self._last_speech_window
        too_short = speech_ms < self.min_turn_speech_ms
        self._in_turn = False
        self._run = 0
        self._speech_windows = 0
        self._silence_windows = 0
        self._turn_start_window = -1
        self._last_speech_window = -1
        if too_short:
            return TurnEvent("discard", window=last, speech_ms=speech_ms,
                             silence_ms=silence_ms, reason="too_short")
        return TurnEvent("speech_end", window=last, speech_ms=speech_ms,
                         silence_ms=silence_ms, reason=reason)
