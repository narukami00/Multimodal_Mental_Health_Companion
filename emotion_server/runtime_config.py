"""Portable asset paths. Set environment variables before starting the service."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MODELS = Path(os.environ.get("SOLACE_EMOTION_MODELS_DIR", str(ROOT / "models"))).expanduser().resolve()
SERVICE = Path(os.environ.get("SOLACE_EMOTION_ARTIFACTS_DIR", str(ROOT / "artifacts"))).expanduser().resolve()
