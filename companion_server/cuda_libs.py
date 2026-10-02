"""Make pip-installed NVIDIA runtime libraries visible to CTranslate2 (Windows).

CTranslate2's CUDA build needs cuBLAS and cuDNN at run time. They are not part of
the faster-whisper / ctranslate2 wheels; `pip install nvidia-cublas-cu12
"nvidia-cudnn-cu12<10"` provides them under `site-packages/nvidia/*/bin`, which
Windows does not search by default. Without them CTranslate2 reports a CUDA device
but fails on first use, and the server silently falls back to the CPU - Whisper is
then roughly ten times slower.

`SOLACE_CUDA_LIBS` may point at a directory that contains the `nvidia/` folder when
the libraries were installed somewhere other than the active environment.
"""

from __future__ import annotations

import ctypes
import glob
import logging
import os
import sys
from typing import Dict, List

logger = logging.getLogger("solace_companion.cuda")

_registered: List[str] = []
_done = False
_probe_cache: Dict[str, bool] = {}

# What CTranslate2 loads on first CUDA use. cuBLAS is needed by everything;
# cuDNN only by Whisper's convolutions.
_LIBS = {
    "cublas": ("cublas64_12.dll", "libcublas.so.12"),
    "cudnn": ("cudnn64_9.dll", "libcudnn.so.9"),
}


def register_cuda_dll_dirs() -> List[str]:
    """Add every `nvidia/*/bin` directory found to the DLL search path. Idempotent."""
    global _done
    if _done:
        return list(_registered)
    _done = True
    if not hasattr(os, "add_dll_directory"):  # Linux/macOS: rely on the loader path
        return []

    roots: List[str] = []
    override = os.environ.get("SOLACE_CUDA_LIBS")
    if override:
        roots.append(override)
    roots.extend(p for p in sys.path if p)

    seen = set()
    for root in roots:
        for bin_dir in glob.glob(os.path.join(root, "nvidia", "*", "bin")):
            bin_dir = os.path.abspath(bin_dir)
            if bin_dir in seen or not os.path.isdir(bin_dir):
                continue
            seen.add(bin_dir)
            try:
                os.add_dll_directory(bin_dir)
                os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
                _registered.append(bin_dir)
            except OSError as err:  # pragma: no cover - unusual filesystem state
                logger.warning(f"Could not register CUDA library dir {bin_dir}: {err}")
    if _registered:
        logger.info(f"CUDA runtime libraries registered from: {_registered}")
    return list(_registered)


def _loadable(lib: str) -> bool:
    """Can the runtime library be loaded right now? Answered without CTranslate2."""
    if lib in _probe_cache:
        return _probe_cache[lib]
    windows_name, linux_name = _LIBS[lib]
    loader = ctypes.WinDLL if os.name == "nt" else ctypes.CDLL
    try:
        loader(windows_name if os.name == "nt" else linux_name)
        ok = True
    except OSError as err:
        logger.warning(
            f"CUDA runtime library {windows_name if os.name == 'nt' else linux_name} "
            f"is not available ({err}). Install it with: "
            'pip install nvidia-cublas-cu12 "nvidia-cudnn-cu12<10"'
        )
        ok = False
    _probe_cache[lib] = ok
    return ok


def cuda_usable(need_cudnn: bool = False) -> bool:
    """True when a CUDA device exists *and* the libraries CTranslate2 will load for it
    are present.

    The libraries are checked here, before CTranslate2 is asked to use the GPU,
    because it lists a device whether or not they exist and then fails on first
    use. After one such failure a second CUDA attempt in the same process can hang
    instead of raising, which left the speech-to-text model never becoming ready.
    """
    register_cuda_dll_dirs()
    try:
        import ctranslate2

        if ctranslate2.get_cuda_device_count() <= 0:
            return False
    except Exception:
        return False
    if not _loadable("cublas"):
        return False
    return _loadable("cudnn") if need_cudnn else True
