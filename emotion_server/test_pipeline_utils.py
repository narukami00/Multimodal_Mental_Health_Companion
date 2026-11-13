"""Unit tests for B1/B2/B3 signal-quality, calibration, and windowing helpers."""

import unittest
import numpy as np

from pipeline_utils import (
    UserBaselineTracker,
    allocate_words_by_weights,
    compute_speech_activity_ratios,
    pool_face_with_quality,
    pool_window_estimates,
)


class TestUserBaselineTracker(unittest.TestCase):
    def test_empirical_bayes_shrinkage_and_reset(self):
        mu_ref = np.array([0.0, 10.0], dtype=np.float32)
        tracker = UserBaselineTracker(k=8.0)
        np.testing.assert_allclose(tracker.effective_mean("A", mu_ref), mu_ref)

        tracker.update("A", np.array([10.0, 20.0], dtype=np.float32))
        tracker.update("A", np.array([10.0, 20.0], dtype=np.float32))
        self.assertEqual(tracker.count("A"), 2)
        # w = 2 / (2 + 8) = 0.2 -> 0.2 * [10, 20] + 0.8 * [0, 10] = [2, 12]
        np.testing.assert_allclose(
            tracker.effective_mean("A", mu_ref),
            np.array([2.0, 12.0], dtype=np.float32),
            atol=1e-5,
        )

        tracker.reset()
        self.assertEqual(tracker.counts(), {})
        np.testing.assert_allclose(tracker.effective_mean("A", mu_ref), mu_ref)


class TestWindowingAndPooling(unittest.TestCase):
    def test_speech_activity_and_word_allocation(self):
        sr = 16000
        silent = np.zeros(sr, dtype=np.float32)
        t = np.linspace(0, 1.0, sr, endpoint=False, dtype=np.float32)
        voiced = 0.2 * np.sin(2 * np.pi * 220.0 * t)

        ratios = compute_speech_activity_ratios([silent, voiced], sr=sr)
        self.assertLess(ratios[0], 0.05)
        self.assertGreater(ratios[1], 0.9)

        words = ["I", "finally", "feel", "steady", "today"]
        segs = allocate_words_by_weights(words, ratios)
        self.assertEqual(segs[0], "")
        self.assertEqual(segs[1], "I finally feel steady today")

    def test_pool_window_estimates_weights_voiced_emotional_peaks(self):
        ests = [
            {
                "pattern": "AT",
                "l7": {"neutral": 0.9, "sad": 0.1},
                "lv": {"negative": 0.05, "neutral": 0.9, "positive": 0.05},
                "la": {"low": 0.3, "mid": 0.5, "high": 0.2},
            },
            {
                "pattern": "AT",
                "l7": {"neutral": 0.1, "sad": 0.9},
                "lv": {"negative": 0.85, "neutral": 0.1, "positive": 0.05},
                "la": {"low": 0.7, "mid": 0.2, "high": 0.1},
            },
        ]
        pooled, summary = pool_window_estimates(ests, [0.0, 1.0])
        self.assertEqual(len(summary), 2)
        self.assertEqual(summary[0]["mood"], "neutral")
        self.assertEqual(summary[1]["mood"], "low")
        self.assertGreater(pooled["lv"]["negative"], 0.80)


class TestFaceQualityPooling(unittest.TestCase):
    def _frame(self, *, usable=1, found=1, blur=120.0, bright=130.0, yaw=0.0, pitch=0.0, val=1.0):
        rec = {
            "usable": usable,
            "found": found,
            "blur": blur,
            "bright": bright,
            "yaw": yaw,
            "pitch": pitch,
            "det_score": 0.95,
            "logits": np.full(8, val, dtype=np.float32),
            "bs": np.full(52, val, dtype=np.float32),
        }
        emb = np.full(1280, val, dtype=np.float32)
        return rec, emb

    def test_quality_weighting_prefers_crisp_frontal_frames_and_drops_extreme_blur(self):
        frames = [
            self._frame(blur=140.0, val=2.0),
            self._frame(blur=130.0, val=2.0),
            self._frame(blur=125.0, val=2.0),
            self._frame(blur=5.0, val=10.0),  # extreme motion blur dropped
        ]
        vec, quality = pool_face_with_quality(frames, min_usable=3)
        self.assertIsNotNone(vec)
        self.assertIsNone(quality["reason"])
        self.assertEqual(quality["usable_frames"], 3)
        self.assertAlmostEqual(float(vec[0]), 2.0, places=4)

    def test_structured_abstention_reasons(self):
        _, q_empty = pool_face_with_quality([])
        self.assertEqual(q_empty["reason"], "no_frames")

        _, q_dark = pool_face_with_quality([self._frame(usable=0, bright=15.0)])
        self.assertEqual(q_dark["reason"], "low_light")

        _, q_none = pool_face_with_quality([self._frame(usable=0, found=0, bright=120.0)])
        self.assertEqual(q_none["reason"], "no_face_detected")


if __name__ == "__main__":
    unittest.main()
