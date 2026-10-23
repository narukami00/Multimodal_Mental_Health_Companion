"""Hands on-phone model packs to the app, so a phone downloads each one once from the person's own server
(never from a third party) and can then work without any connection.

  GET /v1/models/{pack}             -> {"model": "...", "files": [{"name", "size"}]}   (404 when the pack is not set up here)
  GET /v1/models/{pack}/{filename}  -> the file; only names listed for that pack are served

Packs: "stt" (the speech model, folder SOLACE_PHONE_STT_DIR) and "face" (the camera models, folder SOLACE_PHONE_FACE_DIR).
Nothing else on the disk can be reached through these routes.
"""
import os
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

PACKS: Dict[str, Dict[str, Any]] = {
    "stt": {
        "model": "whisper-base.en",
        "env": "SOLACE_PHONE_STT_DIR",
        "files": ("base.en-encoder.int8.onnx", "base.en-decoder.int8.onnx", "base.en-tokens.txt"),
    },
    "face": {
        "model": "face-v1",  # EfficientNet-B0 (emotion features), YuNet (face finder), MediaPipe face landmarker (expressions, pose)
        "env": "SOLACE_PHONE_FACE_DIR",
        "files": ("b0_fp32.onnx", "face_detection_yunet_2023mar.onnx", "face_landmarker.task"),
    },
}
MODEL_NAME = PACKS["stt"]["model"]  # kept for the first version of the speech-only routes
FILES = PACKS["stt"]["files"]


def model_dir(pack: str = "stt") -> Optional[Path]:
    spec = PACKS.get(pack)
    if spec is None:
        return None
    raw = os.environ.get(spec["env"], "").strip()
    if not raw:
        return None
    path = Path(raw)
    return path if path.is_dir() and all((path / name).is_file() for name in spec["files"]) else None


def manifest(pack: str = "stt") -> Optional[Dict[str, Any]]:
    folder = model_dir(pack)
    if folder is None:
        return None
    spec = PACKS[pack]
    return {"model": spec["model"], "files": [{"name": name, "size": (folder / name).stat().st_size} for name in spec["files"]]}


def build_router() -> APIRouter:
    router = APIRouter()

    @router.get("/v1/models/{pack}")
    async def pack_manifest(pack: str) -> Dict[str, Any]:
        result = manifest(pack)
        if result is None:
            raise HTTPException(status_code=404, detail="that model is not set up on this server")
        return result

    @router.get("/v1/models/{pack}/{filename}")
    async def pack_file(pack: str, filename: str) -> FileResponse:
        folder = model_dir(pack)
        if folder is None or filename not in PACKS[pack]["files"]:  # an allow-list: no path can name anything else
            raise HTTPException(status_code=404, detail="not found")
        return FileResponse(folder / filename, media_type="application/octet-stream")

    return router
