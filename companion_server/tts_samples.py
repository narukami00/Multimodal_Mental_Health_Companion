"""Makes voice samples to listen to, so the voice is chosen by ear.

It synthesises a few sentences Sol might say with different engines, voices, speeds and pauses, saves each as a WAV at the model's own
sample rate (nothing is resampled), and writes `index.html` with a player for every clip, grouped by setting.

Run (from companion_server):  python tts_samples.py --out PATH/tts_samples --engine piper
Options: --engine piper|kokoro|both   --models-dir PATH   --voices af_heart,af_bella   --speeds 1.0,0.92
Kokoro needs the `kokoro-multi-lang-v1_0` files in --models-dir (model.onnx, voices.bin, tokens.txt, lexicon-*.txt, espeak-ng-data).
"""
import argparse
import html
import sys
import wave
from pathlib import Path
from typing import Dict, List, Optional

import numpy as np

from tts_text import normalize_for_speech, split_clauses

SENTENCES = [
    ("warm", "That sounds like a really lovely morning. I'm so glad your sister called, and that you got to laugh together."),
    ("low", "It's okay to feel low sometimes. You don't have to figure it all out right now; we can just sit with it for a while."),
    ("question", "What was the best part of today, even if it was small? Take your time, there's no rush."),
    ("numbers", "You walked about 5,000 steps today, and the rickshaw cost Tk 250. A year of that is nearly 1 lakh, which is a lot to carry."),
]

# Pauses (seconds) inserted between clauses when a clip is made clause by clause.
PAUSES = {",": 0.16, ";": 0.22, ":": 0.2, ".": 0.36, "!": 0.36, "?": 0.4}


def write_wav(path: Path, samples: np.ndarray, rate: int) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def synth_whole(engine, text: str, voice: Optional[str], speed: float) -> np.ndarray:
    return engine.synthesize(text, voice_id=voice, speed=speed).samples


def synth_by_clause(engine, text: str, voice: Optional[str], speed: float, rate: int) -> np.ndarray:
    """Each clause on its own with a short silence after it: steadier pacing than one long run-on breath."""
    parts: List[np.ndarray] = []
    for clause, mark in split_clauses(text):
        parts.append(engine.synthesize(clause, voice_id=voice, speed=speed).samples)
        parts.append(np.zeros(int(PAUSES.get(mark, 0.2) * rate), dtype=np.float32))
    return np.concatenate(parts) if parts else np.zeros(0, dtype=np.float32)


def build_engine(kind: str, models_dir: Path):
    from tts_engine import SherpaOnnxTtsEngine

    if kind == "piper":
        engine = SherpaOnnxTtsEngine(
            model_path=models_dir / "en_US-amy-low.onnx", tokens_path=models_dir / "tokens.txt",
            data_dir=models_dir / "espeak-ng-data", is_kokoro=False,
        )
    else:
        kdir = models_dir / "kokoro-multi-lang-v1_0"
        engine = SherpaOnnxTtsEngine(
            model_path=kdir / "model.onnx", tokens_path=kdir / "tokens.txt", voices_path=kdir / "voices.bin",
            data_dir=kdir / "espeak-ng-data", is_kokoro=True,
        )
    if not engine.initialize():
        raise SystemExit(f"Could not load the {kind} engine from {models_dir}")
    return engine


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--engine", default="piper", choices=["piper", "kokoro", "both"])
    parser.add_argument("--models-dir", default=str(Path(__file__).resolve().parent / "models" / "tts"))
    parser.add_argument("--voices", default="af_heart,af_bella,af_sarah,am_michael")
    parser.add_argument("--speeds", default="1.0,0.92")
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    models = Path(args.models_dir)
    speeds = [float(s) for s in args.speeds.split(",")]
    voices = [v.strip() for v in args.voices.split(",") if v.strip()]
    kinds = ["piper", "kokoro"] if args.engine == "both" else [args.engine]

    groups: Dict[str, List[tuple]] = {}
    for kind in kinds:
        engine = build_engine(kind, models)
        rate = engine.default_sample_rate
        voice_list = voices if kind == "kokoro" else [None]
        for voice in voice_list:
            for speed in speeds:
                for style in ("whole", "clauses"):
                    label = f"{kind}{'-' + voice if voice else ''} | speed {speed} | {style}"
                    folder = out / label.replace(" | ", "_").replace(" ", "")
                    folder.mkdir(exist_ok=True)
                    for key, text in SENTENCES:
                        spoken = normalize_for_speech(text)
                        samples = synth_whole(engine, spoken, voice, speed) if style == "whole" else synth_by_clause(engine, spoken, voice, speed, rate)
                        path = folder / f"{key}.wav"
                        write_wav(path, samples, rate)
                        groups.setdefault(f"{label}  ({rate} Hz)", []).append((key, text, path.relative_to(out).as_posix()))
        print(f"{kind}: done ({rate} Hz)")

    rows = []
    for label, clips in groups.items():
        rows.append(f"<h3>{html.escape(label)}</h3>")
        for key, text, rel in clips:
            rows.append(f"<p><b>{html.escape(key)}</b>: {html.escape(text)}<br><audio controls preload='none' src='{html.escape(rel)}'></audio></p>")
    (out / "index.html").write_text(
        "<!doctype html><meta charset='utf-8'><title>Sol voice samples</title>"
        "<style>body{font-family:system-ui;max-width:760px;margin:24px auto;padding:0 16px;line-height:1.4}audio{width:100%}</style>"
        "<h1>Sol voice samples</h1><p>Listen on the same speakers you will use. Note the setting that sounds best.</p>" + "".join(rows),
        encoding="utf-8",
    )
    print(f"{sum(len(c) for c in groups.values())} clips in {out}\nOpen {out / 'index.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
