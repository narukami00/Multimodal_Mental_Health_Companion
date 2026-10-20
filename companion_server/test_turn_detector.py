"""Unit tests for the server-side turn detector. Pure: no models, no server."""

from turn_detector import TurnDetector, WINDOW_MS


def feed(detector: TurnDetector, probs):
    events = []
    for p in probs:
        events.extend(detector.push(p))
    return events


def windows(ms: int) -> int:
    return -(-ms // WINDOW_MS)


def test_noise_never_opens_a_turn():
    d = TurnDetector()
    assert feed(d, [0.05] * 2000) == []
    assert not d.in_turn


def test_a_click_is_not_a_turn():
    d = TurnDetector(min_speech_ms=128)
    # Two speech windows (64 ms) is shorter than the 128 ms onset confirmation.
    assert feed(d, [0.0] * 20 + [0.9, 0.9] + [0.0] * 40) == []


def test_speech_then_silence_ends_exactly_once():
    d = TurnDetector(endpoint_ms=640, min_speech_ms=96)
    events = feed(d, [0.0] * 10 + [0.9] * 50 + [0.0] * 40)
    kinds = [e.kind for e in events]
    assert kinds == ["speech_start", "speech_end"]
    start, end = events
    assert start.window == 10
    assert end.window == 10 + 50 - 1
    assert end.reason == "silence"
    assert end.speech_ms == 50 * WINDOW_MS
    assert not d.in_turn


def test_endpoint_waits_for_the_full_silence_deadline():
    d = TurnDetector(endpoint_ms=640, min_speech_ms=96)
    events = feed(d, [0.9] * 30)
    assert [e.kind for e in events] == ["speech_start"]
    # One window short of the deadline: still the same turn.
    assert feed(d, [0.0] * (windows(640) - 1)) == []
    assert d.in_turn
    assert [e.kind for e in feed(d, [0.0])] == ["speech_end"]


def test_a_pause_shorter_than_the_deadline_does_not_split_the_turn():
    d = TurnDetector(endpoint_ms=640, min_speech_ms=96)
    pause = [0.0] * (windows(640) - 2)
    events = feed(d, [0.9] * 20 + pause + [0.9] * 20 + [0.0] * 40)
    assert [e.kind for e in events] == ["speech_start", "speech_end"]
    assert events[1].speech_ms == 40 * WINDOW_MS


def test_ambiguous_probabilities_do_not_reset_the_onset_run():
    d = TurnDetector(min_speech_ms=128, neg_threshold=0.35)
    # 0.42 sits between the thresholds: neither confirms nor denies.
    events = feed(d, [0.9, 0.9, 0.42, 0.9, 0.9])
    assert [e.kind for e in events] == ["speech_start"]


def test_borderline_noise_still_ends_the_turn():
    """Probabilities that hover just under the threshold are silence, not speech.

    This is the failure that made the old client gate never close: a floor that
    sat a few dB below room noise counted every frame as speech.
    """
    d = TurnDetector(endpoint_ms=640, min_speech_ms=96)
    events = feed(d, [0.9] * 20 + [0.45] * 40)
    assert [e.kind for e in events] == ["speech_start", "speech_end"]


def test_too_short_a_turn_is_discarded_not_answered():
    d = TurnDetector(min_speech_ms=96, min_turn_speech_ms=250, endpoint_ms=320)
    events = feed(d, [0.9] * 4 + [0.0] * 20)  # 128 ms of speech
    assert [e.kind for e in events] == ["speech_start", "discard"]
    assert events[1].reason == "too_short"


def test_a_turn_that_never_goes_quiet_is_capped():
    d = TurnDetector(max_turn_ms=3000, min_speech_ms=96)
    events = feed(d, [0.9] * 500)
    kinds = [e.kind for e in events]
    assert kinds[0] == "speech_start"
    assert "speech_end" in kinds
    end = next(e for e in events if e.kind == "speech_end")
    assert end.reason == "max_duration"


def test_force_end_closes_the_open_turn_and_reports_it():
    d = TurnDetector(min_speech_ms=96)
    feed(d, [0.9] * 30)
    event = d.force_end("client_end")
    assert event is not None and event.kind == "speech_end"
    assert event.reason == "client_end"
    assert d.force_end() is None


def test_detector_is_reusable_after_a_turn():
    d = TurnDetector(endpoint_ms=320, min_speech_ms=96)
    first = feed(d, [0.9] * 20 + [0.0] * 20)
    second = feed(d, [0.0] * 5 + [0.9] * 20 + [0.0] * 20)
    assert [e.kind for e in first] == ["speech_start", "speech_end"]
    assert [e.kind for e in second] == ["speech_start", "speech_end"]


def test_reset_drops_an_open_turn_silently():
    d = TurnDetector(min_speech_ms=96)
    feed(d, [0.9] * 30)
    assert d.in_turn
    d.reset()
    assert not d.in_turn
    assert feed(d, [0.0] * 100) == []
