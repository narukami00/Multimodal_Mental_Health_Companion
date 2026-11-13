# Solace reference emotion service

This is a portable source extraction of the **existing demo model v0**. It is a reference inference backend for the self-care app, separate from the new research pipeline. It is not a diagnostic model or a dependable crisis detector. No clinical benefit has been established.

## Contents and provenance

`emotion_api.py`, `emotion_engine.py` and `cue.py` were copied from the developer's current reference engine (`scripts/emotion_service`). `heads.py` contains only the unchanged `NetVA` inference class from `scripts/modeling/va_head.py`; `face_runtime.py` extracts its face constants and geometry helpers from `cache_faces_v2.py`. Research/training imports and machine-specific paths were replaced with `runtime_config.py`. The HTTP service does not run VAD, so its unused eager Silero model load was removed. The original cue tests were ported to standard-library unittest. Existing app and companion launchers have not been changed.

No datasets, personal recordings, logs, pretrained backbones or trained weights are bundled. Asset access and redistribution permission still need to be established before a public release. This extraction does not grant a new license to upstream assets or code.

## Assets required

Set `SOLACE_EMOTION_MODELS_DIR` to a directory containing:

| Directory/file | Use |
| --- | --- |
| `wavlm-large/` | Local Transformers WavLM-large encoder with its feature extractor and weights; upstream revision/provenance must be pinned |
| `whisper-small/` | Local `openai/whisper-small` configuration, feature extractor and weights |
| `embeddinggemma-2/` | Local SentenceTransformer EmbeddingGemma-2 model including tokenizer and module metadata; source notes identify `google/embeddinggemma-2`, but upstream revision/license must be verified |
| `face/face_detection_yunet_2023mar.onnx` | Optional YuNet face detector |
| `face/face_landmarker.task` | Optional MediaPipe face landmarker |
| `face/enet_b0_8_best_afew_tf_statedict.pt` | Optional EfficientNet-B0 emotion weights loaded into timm `tf_efficientnet_b0` |

Set `SOLACE_EMOTION_ARTIFACTS_DIR` to the directory containing `heads_s0.pt` through `heads_s4.pt`, `temps.json`, and `ref_stats.npz`. Exact observed sizes and SHA256 values are in `artifact_manifest.json`. Only load trusted checkpoints. The five heads total approximately 82 MB. All seven artifacts were found in the source workstation; they are not included in this directory. No raw training data are needed for inference once these artifacts and backbones are supplied.

The checkpoints use audio vectors of 10,752 values, text vectors of 3,072 values and optional face vectors of 1,400 values. Five production heads are averaged and temperature-scaled for each available-modality pattern. Default inference normalization uses MOSEI reference statistics; this creates domain-shift limitations.

## Setup and run

Use an isolated Python environment. `environment-observed.txt` records versions inspected from source environment metadata; it is **not** a complete tested lock. That environment used Python 3.13.4 with dependencies spread across two environments. `requirements.txt` supplies runtime dependency bounds; a clean installation and exact lock still need validation. CUDA wheel installation depends on the target machine.

From this directory in PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
$env:SOLACE_EMOTION_MODELS_DIR = 'C:\path\to\models'
$env:SOLACE_EMOTION_ARTIFACTS_DIR = 'C:\path\to\service-artifacts'
python check_assets.py --verify-hashes
$env:EMOTION_FACE = '0'
python -m uvicorn emotion_api:app --host 127.0.0.1 --port 8766
```

For server-side camera processing, set `EMOTION_FACE=1` and run `python check_assets.py --verify-hashes --face` before startup. Keep this unauthenticated reference service on localhost. On-phone derived face vectors can be ingested without the server's face-processing models; consent must be enforced by the calling app/companion.

Configure the companion server with `SOLACE_EMOTION=1` and `SOLACE_EMOTION_URL=http://127.0.0.1:8766`; the app must separately opt in. The reference API exposes `/healthz`, `/v1/emotion/audio`, `/finalize`, `/text`, `/frame`, `/face_vector`, and `/reset` (all emotion endpoints have prefix `/v1/emotion`). See the module docstring for payloads. It returns estimates and optional hedged tone cues; uncertainty suppresses cues and face-only estimates never drive companion tone. The separate companion safety gate remains necessary.

## Verification and limits

```powershell
python -m unittest discover -s . -p 'test_cue.py' -v
python check_assets.py --verify-hashes
```

Cue tests need no ML dependencies, models or network. The asset checker imports no ML libraries and never deserializes weights. A successful presence check is not a successful model load: pretrained backbone identities/revisions, tokenizer completeness, live inference, capture-path parity, memory usage and latency still require integration validation. There is no bundled synthetic inference substitute.

The source workstation has grouped evaluation code and a preregistered MELD holdout result. Its primary MOSEI-reference normalization result is about **0.269 seven-class macro-F1 for ATV**, versus **0.266 for text alone** on the paired set; this does not demonstrate a useful multimodal advantage out of domain. A secondary result using statistics computed from the MELD test inputs reaches about **0.322**, but is transductive and must not be presented as ordinary unseen-user performance. These source artifacts have not been independently rerun here. Research benchmarks are not evidence of clinical effectiveness or real-user retention.
