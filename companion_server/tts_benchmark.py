"""How fast the voice is made: time to speak one clause, against how long that clause lasts.

A clause is spoken while the previous one plays, so what matters is (1) the wait before the FIRST clause is heard and (2) whether every later clause
is ready before the one before it ends (real-time factor below 1.0). Prints a table by number of CPU threads and clause length.

Run (from companion_server):  python tts_benchmark.py [--threads 2,4,6,8] [--voice af_bella] [--reps 3]
"""
import argparse
import statistics
import sys
import time
from pathlib import Path

from tts_engine import SherpaOnnxTtsEngine

CLAUSES = {
    "short": "That sounds lovely.",
    "medium": "I'm so glad your sister called, and that you got to laugh together.",
    "long": "It's okay to feel low sometimes, and you don't have to figure it all out right now; we can just sit with it for a while.",
}


def build(kokoro_dir: Path, threads: int) -> SherpaOnnxTtsEngine:
    engine = SherpaOnnxTtsEngine(
        model_path=kokoro_dir / "model.onnx", tokens_path=kokoro_dir / "tokens.txt", voices_path=kokoro_dir / "voices.bin",
        data_dir=kokoro_dir / "espeak-ng-data", lexicon_path=kokoro_dir / "lexicon-us-en.txt", is_kokoro=True, num_threads=threads,
    )
    if not engine.initialize():
        raise SystemExit("Kokoro did not load")
    return engine


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kokoro-dir", default="F:/__Downloads/envs/tts_models/kokoro-multi-lang-v1_0")
    parser.add_argument("--threads", default="2,4,6,8")
    parser.add_argument("--voice", default="af_bella")
    parser.add_argument("--reps", type=int, default=3)
    args = parser.parse_args()

    print(f"{'threads':>7} {'clause':>7} {'audio s':>8} {'took ms':>8} {'speed x real-time':>18}")
    for threads in (int(t) for t in args.threads.split(",")):
        t0 = time.time()
        engine = build(Path(args.kokoro_dir), threads)
        load = time.time() - t0
        engine.synthesize("Warm up.", voice_id=args.voice)  # the first call pays one-off costs
        for name, text in CLAUSES.items():
            took, audio = [], 0.0
            for _ in range(args.reps):
                t = time.time()
                result = engine.synthesize(text, voice_id=args.voice, speed=1.0)
                took.append(time.time() - t)
                audio = result.duration_sec
            median = statistics.median(took)
            print(f"{threads:>7} {name:>7} {audio:>8.1f} {median * 1000:>8.0f} {audio / median:>17.1f}x")
        print(f"        (model load {load:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
