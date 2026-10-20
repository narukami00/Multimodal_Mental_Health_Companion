"""Set up the local Piper voice: fetch the espeak-ng data it needs.

The Piper model (`models/tts/en_US-amy-low.onnx` + `tokens.txt`) cannot speak
without espeak-ng's phoneme data, and without it the server quietly falls back to
the cloud Edge voice (about 1.5 s per clause, and it needs the internet).

    python setup_local_voice.py            # downloads ~9 MB from PyPI, once
    set SOLACE_TTS=piper                   # then start the server

The data comes from the `espeakng-loader` package on PyPI, which bundles it.
Nothing is installed: the wheel is downloaded, the data folder copied out, and the
wheel discarded.
"""

import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

TTS_DIR = Path(__file__).resolve().parent / "models" / "tts"


def main() -> int:
    target = TTS_DIR / "espeak-ng-data"
    if target.exists():
        print(f"{target} already exists; nothing to do.")
        return 0
    TTS_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            [sys.executable, "-m", "pip", "download", "espeakng-loader", "--no-deps", "-d", tmp],
            check=True,
        )
        wheel = next(Path(tmp).glob("espeakng_loader-*.whl"))
        with zipfile.ZipFile(wheel) as zf:
            members = [m for m in zf.namelist() if m.startswith("espeakng_loader/espeak-ng-data/")]
            zf.extractall(tmp, members)
        shutil.copytree(Path(tmp) / "espeakng_loader" / "espeak-ng-data", target)
    print(f"espeak-ng data is in {target}")
    print("Start the server with SOLACE_TTS=piper to use the local voice.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
