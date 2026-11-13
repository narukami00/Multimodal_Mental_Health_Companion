"""Inspect assets without importing ML libraries or deserializing weights."""
import argparse
import hashlib
import json
from pathlib import Path

from runtime_config import MODELS, ROOT, SERVICE


def inspect(verify_hashes=False, face=False):
    manifest = json.loads((ROOT / "artifact_manifest.json").read_text())
    results = []
    for item in manifest["artifacts"]:
        path = SERVICE / item["path"]
        status = "missing"
        if path.is_file():
            status = "size_matches" if path.stat().st_size == item["size_bytes"] else "size_mismatch"
            if verify_hashes:
                with path.open("rb") as stream:
                    digest = hashlib.file_digest(stream, "sha256").hexdigest()
                status = "verified" if digest == item["sha256"] else "hash_mismatch"
        results.append({"artifact": item["path"], "status": status})
    for name in ("wavlm-large", "whisper-small", "embeddinggemma-2"):
        path = MODELS / name
        # Presence is only a preliminary check; encoder loading is the integration check.
        weights_present = any(path.glob("*.safetensors")) or (path / "pytorch_model.bin").is_file()
        present = (path / "config.json").is_file() and weights_present
        results.append({"artifact": name, "status": "present_unverified" if present else "missing"})
    if face:
        for name in ("face_detection_yunet_2023mar.onnx", "face_landmarker.task", "enet_b0_8_best_afew_tf_statedict.pt"):
            results.append({"artifact": "face/" + name, "status": "present_unverified" if (MODELS / "face" / name).is_file() else "missing"})
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-hashes", action="store_true")
    parser.add_argument("--face", action="store_true")
    args = parser.parse_args()
    rows = inspect(args.verify_hashes, args.face)
    print(json.dumps({"artifacts_dir": str(SERVICE), "models_dir": str(MODELS), "results": rows}, indent=2))
    raise SystemExit(1 if any(row["status"] in {"missing", "hash_mismatch", "size_mismatch"} for row in rows) else 0)
