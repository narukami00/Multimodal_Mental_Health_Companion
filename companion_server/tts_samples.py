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


def build_engine(kind: str, models_dir: Path, kokoro_dir: Path):
    from tts_engine import SherpaOnnxTtsEngine

    if kind == "piper":
        engine = SherpaOnnxTtsEngine(
            model_path=models_dir / "en_US-amy-low.onnx", tokens_path=models_dir / "tokens.txt",
            data_dir=models_dir / "espeak-ng-data", is_kokoro=False,
        )
    else:
        engine = SherpaOnnxTtsEngine(
            model_path=kokoro_dir / "model.onnx", tokens_path=kokoro_dir / "tokens.txt", voices_path=kokoro_dir / "voices.bin",
            data_dir=kokoro_dir / "espeak-ng-data", lexicon_path=kokoro_dir / "lexicon-us-en.txt", is_kokoro=True,
        )
    if not engine.initialize():
        raise SystemExit(f"Could not load the {kind} engine from {models_dir}")
    return engine


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--engine", default="piper", choices=["piper", "kokoro", "both"])
    parser.add_argument("--models-dir", default=str(Path(__file__).resolve().parent / "models" / "tts"))
    parser.add_argument("--kokoro-dir", default="F:/__Downloads/envs/tts_models/kokoro-multi-lang-v1_0")
    parser.add_argument("--voices", default="af_heart,af_bella,af_sarah,af_nicole,af_sky,am_michael,am_adam")
    parser.add_argument("--speeds", default="1.0,0.92")
    parser.add_argument("--styles", default="whole,clauses")
    parser.add_argument("--rebuild", action="store_true", help="only rebuild index.html from clips already made")
    args = parser.parse_args()

    if args.rebuild:
        return rebuild(Path(args.out))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    models = Path(args.models_dir)
    speeds = [float(s) for s in args.speeds.split(",")]
    voices = [v.strip() for v in args.voices.split(",") if v.strip()]
    kinds = ["piper", "kokoro"] if args.engine == "both" else [args.engine]

    groups: Dict[str, List[tuple]] = {}
    for kind in kinds:
        engine = build_engine(kind, models, Path(args.kokoro_dir))
        rate = engine.default_sample_rate
        voice_list = voices if kind == "kokoro" else [None]
        for voice in voice_list:
            for speed in speeds:
                for style in args.styles.split(","):
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

    write_index(out, groups)
    print(f"{sum(len(c) for c in groups.values())} clips in {out}\nOpen {out / 'index.html'}")
    return 0


def audio_data_uri(wav_path: Path) -> str:
    """The clip as a data: URI, so the page plays anywhere, even as a snapshot that cannot reach the files beside it.
    Compressed to MP3 when ffmpeg is available (about a tenth of the size), otherwise embedded as the WAV."""
    import base64
    import shutil
    import subprocess
    import tempfile

    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        with tempfile.TemporaryDirectory() as tmp:
            mp3 = Path(tmp) / "clip.mp3"
            done = subprocess.run([ffmpeg, "-loglevel", "error", "-y", "-i", str(wav_path), "-codec:a", "libmp3lame", "-b:a", "96k", str(mp3)])
            if done.returncode == 0 and mp3.exists():
                return "data:audio/mpeg;base64," + base64.b64encode(mp3.read_bytes()).decode()
    return "data:audio/wav;base64," + base64.b64encode(wav_path.read_bytes()).decode()


def clip_seconds(wav_path: Path) -> float:
    with wave.open(str(wav_path)) as w:
        return w.getnframes() / w.getframerate()


def write_index(out: Path, groups: Dict[str, List[tuple]]) -> None:
    rows = []
    for label, clips in groups.items():
        rows.append(f"<h3>{html.escape(label)}</h3>")
        for key, text, rel in clips:
            wav = out / rel
            rows.append(
                f"<p><b>{html.escape(key)}</b> <small>({clip_seconds(wav):.1f} s)</small>: {html.escape(text)}<br>"
                f"<audio controls preload='metadata' src='{audio_data_uri(wav)}'></audio></p>"
            )
    (out / "index.html").write_text(
        "<!doctype html><meta charset='utf-8'><title>Sol voice samples</title>"
        "<style>body{font-family:system-ui;max-width:760px;margin:24px auto;padding:0 16px;line-height:1.4}audio{width:100%}h3{margin-top:28px}</style>"
        "<h1>Sol voice samples</h1><p>Listen on the same speakers you will use. Note the setting that sounds best.</p>" + "".join(rows),
        encoding="utf-8",
    )


def rebuild(out: Path) -> int:
    """Rebuilds index.html from clips already made (no synthesis), for when only the page needs to change."""
    groups: Dict[str, List[tuple]] = {}
    texts = dict(SENTENCES)
    for folder in sorted(p for p in out.iterdir() if p.is_dir()):
        rate = wave.open(str(next(folder.glob("*.wav")))).getframerate()
        label = folder.name.replace("_", " | ", 1).replace("_", " | ")
        for key, _ in SENTENCES:
            wav = folder / f"{key}.wav"
            if wav.exists():
                groups.setdefault(f"{label}  ({rate} Hz)", []).append((key, texts[key], wav.relative_to(out).as_posix()))
    write_index(out, groups)
    print(f"rebuilt {out / 'index.html'} from {sum(len(c) for c in groups.values())} clips")
    return 0


if __name__ == "__main__":
    sys.exit(main())
