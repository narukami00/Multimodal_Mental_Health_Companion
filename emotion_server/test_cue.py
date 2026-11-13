"""Model-free cue tests ported from the reference pytest cases."""

import unittest

from cue import EmotionState, build_cue, safety_category

CLASS_WORDS = ("sad", "angry", "fear", "disgust", "happy", "surprise", "neutral emotion")

def est(neg=0.1, neu=0.2, pos=0.7, low=0.2, high=0.6, pattern='AT'):
    return {'pattern': pattern, 'l7': {'neutral': 0.5, 'happy': 0.5}, 'lv': {'negative': neg, 'neutral': neu, 'positive': pos}, 'la': {'low': low, 'mid': 1 - low - high, 'high': high}}

def test_neutral_turn_has_no_cue():
    out = build_cue(est(neg=0.1, neu=0.8, pos=0.1), EmotionState())
    assert out['cue'] is None and out['suppressed']

def test_uncertain_turn_has_no_cue():
    out = build_cue(est(neg=0.4, neu=0.3, pos=0.3), EmotionState())
    assert out['cue'] is None

def test_clear_negative_low_arousal_gives_hedged_cue_without_class_names():
    out = build_cue(est(neg=0.8, neu=0.1, pos=0.1, low=0.7, high=0.1), EmotionState())
    assert out['cue'] and 'low or tired' in out['cue'] and (out['tier'] == 'clear')
    assert 'weak guess' in out['cue'] and 'ignore this note' in out['cue']
    assert not any((w in out['cue'].lower() for w in CLASS_WORDS))
    assert len(out['cue']) < 420

def test_hint_tier_is_marked_very_weak():
    out = build_cue(est(neg=0.55, neu=0.3, pos=0.15, low=0.5, high=0.2), EmotionState())
    assert out['cue'] and out['tier'] == 'hint' and ('very weak' in out['cue'])

def test_text_only_needs_a_higher_bar():
    assert build_cue(est(neg=0.52, neu=0.3, pos=0.18, pattern='T'), EmotionState())['cue'] is None
    assert build_cue(est(neg=0.7, neu=0.2, pos=0.1, pattern='T'), EmotionState())['cue'] is not None

def test_one_positive_turn_does_not_flip_a_negative_run():
    s = EmotionState()
    for _ in range(3):
        build_cue(est(neg=0.85, neu=0.1, pos=0.05, low=0.7, high=0.1), s)
    out = build_cue(est(neg=0.1, neu=0.2, pos=0.7, low=0.1, high=0.7), s)
    assert out['cue'] is None and 'disagrees' in out['suppressed']

def test_negative_high_arousal_and_positive_moods():
    assert 'tense or upset' in build_cue(est(neg=0.8, neu=0.1, pos=0.1, low=0.1, high=0.7), EmotionState())['cue']
    assert 'upbeat' in build_cue(est(neg=0.05, neu=0.15, pos=0.8, low=0.1, high=0.7), EmotionState())['cue']
    assert 'calm or content' in build_cue(est(neg=0.05, neu=0.15, pos=0.8, low=0.7, high=0.1), EmotionState())['cue']

def test_self_harm_language_suppresses_the_cue_and_flags_0():
    text = 'I will kill myself'
    out = build_cue(est(neg=0.9, neu=0.05, pos=0.05, low=0.8, high=0.1), EmotionState(), text)
    assert out['cue'] is None and out['safety'] == 'self_harm_language' and ('matched' not in out)

def test_self_harm_language_suppresses_the_cue_and_flags_1():
    text = 'I want to die.'
    out = build_cue(est(neg=0.9, neu=0.05, pos=0.05, low=0.8, high=0.1), EmotionState(), text)
    assert out['cue'] is None and out['safety'] == 'self_harm_language' and ('matched' not in out)

def test_self_harm_language_suppresses_the_cue_and_flags_2():
    text = "i'm thinking about suicide"
    out = build_cue(est(neg=0.9, neu=0.05, pos=0.05, low=0.8, high=0.1), EmotionState(), text)
    assert out['cue'] is None and out['safety'] == 'self_harm_language' and ('matched' not in out)

def test_self_harm_language_suppresses_the_cue_and_flags_3():
    text = "I don't want to be here anymore"
    out = build_cue(est(neg=0.9, neu=0.05, pos=0.05, low=0.8, high=0.1), EmotionState(), text)
    assert out['cue'] is None and out['safety'] == 'self_harm_language' and ('matched' not in out)

def test_self_harm_language_suppresses_the_cue_and_flags_4():
    text = 'I might hurt myself tonight'
    out = build_cue(est(neg=0.9, neu=0.05, pos=0.05, low=0.8, high=0.1), EmotionState(), text)
    assert out['cue'] is None and out['safety'] == 'self_harm_language' and ('matched' not in out)

def test_self_harm_language_suppresses_the_cue_and_flags_5():
    text = "They'd be better off without me"
    out = build_cue(est(neg=0.9, neu=0.05, pos=0.05, low=0.8, high=0.1), EmotionState(), text)
    assert out['cue'] is None and out['safety'] == 'self_harm_language' and ('matched' not in out)

def test_ordinary_sentences_are_not_flagged_0():
    text = 'I am killing it at work today'
    assert safety_category(text) is None

def test_ordinary_sentences_are_not_flagged_1():
    text = 'this traffic is killing me'
    assert safety_category(text) is None

def test_ordinary_sentences_are_not_flagged_2():
    text = 'My dog died last week and I feel awful'
    assert safety_category(text) is None

def test_ordinary_sentences_are_not_flagged_3():
    text = 'I killed the process'
    assert safety_category(text) is None

def test_known_false_positive_is_visible():
    assert safety_category('I want to die laughing at that video') == 'self_harm_language'

def test_reset_clears_state():
    s = EmotionState()
    build_cue(est(), s)
    s.reset()
    assert s.v is None and s.turns == 0


def test_turn_gap_decay_prevents_stale_run_from_blocking_fresh_turn():
    s = EmotionState(half_life_s=300.0)
    for i in range(3):
        build_cue(est(neg=0.85, neu=0.1, pos=0.05, low=0.7, high=0.1), s, now=100.0 + i)
    # One hour later, prior negative EMA has decayed so a clear positive turn comes through.
    out = build_cue(est(neg=0.05, neu=0.15, pos=0.8, low=0.2, high=0.6), s, now=3700.0)
    assert out['cue'] is not None and out['mood'] == 'upbeat'


def test_cross_modal_incongruence_emits_hedged_mixed_note():
    e = est(neg=0.45, neu=0.25, pos=0.30, pattern='AT')
    e['modalities'] = {
        'A': {'negative': 0.72, 'neutral': 0.18, 'positive': 0.10},
        'T': {'negative': 0.10, 'neutral': 0.20, 'positive': 0.70},
    }
    out = build_cue(e, EmotionState(), text="I am doing totally fine today")
    assert out['incongruent'] is True
    assert out['mood'] == 'mixed signals'
    assert out['cue'] and 'quiet tension' in out['cue']


def test_shared_safety_phrases_floor():
    out = build_cue(est(neg=0.8, neu=0.1, pos=0.1), EmotionState(), text='I feel like self harm tonight')
    assert out['cue'] is None and out['safety'] == 'self_harm_language'

def test_face_only_never_gives_a_cue_and_never_moves_the_state():
    state = EmotionState()
    est = dict(pattern='V', lv=dict(negative=0.9, neutral=0.05, positive=0.05), la=dict(low=0.1, mid=0.1, high=0.8))
    d = build_cue(est, state, '')
    assert d['cue'] is None and d['tier'] is None and ('face only' in d['suppressed'])
    assert state.turns == 0 and state.v is None

class CueTests(unittest.TestCase):

    pass

for _name, _fn in list(globals().items()):

    if _name.startswith("test_") and callable(_fn):

        setattr(CueTests, _name, lambda self, fn=_fn: fn())

del _name, _fn

if __name__ == "__main__":

    unittest.main()
