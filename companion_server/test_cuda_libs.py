"""The CUDA preflight must refuse the GPU *before* CTranslate2 is asked to use it.

CTranslate2 reports a CUDA device whether or not cuBLAS / cuDNN exist, and a failed
first use can make the next CUDA attempt in the same process hang instead of
raise. That is how the speech-to-text model once never became ready, so the
check is pinned here without needing a GPU.
"""

import ctranslate2
import pytest

import cuda_libs


@pytest.fixture(autouse=True)
def one_device(monkeypatch):
    monkeypatch.setattr(ctranslate2, "get_cuda_device_count", lambda: 1)


def test_missing_cublas_means_no_gpu_for_anyone(monkeypatch):
    monkeypatch.setattr(cuda_libs, "_probe_cache", {"cublas": False, "cudnn": True})
    assert cuda_libs.cuda_usable() is False
    assert cuda_libs.cuda_usable(need_cudnn=True) is False


def test_cudnn_is_only_required_by_whisper(monkeypatch):
    monkeypatch.setattr(cuda_libs, "_probe_cache", {"cublas": True, "cudnn": False})
    assert cuda_libs.cuda_usable() is True               # the language model
    assert cuda_libs.cuda_usable(need_cudnn=True) is False  # Whisper's convolutions


def test_everything_present_means_gpu(monkeypatch):
    monkeypatch.setattr(cuda_libs, "_probe_cache", {"cublas": True, "cudnn": True})
    assert cuda_libs.cuda_usable(need_cudnn=True) is True


def test_no_device_means_no_gpu(monkeypatch):
    monkeypatch.setattr(ctranslate2, "get_cuda_device_count", lambda: 0)
    monkeypatch.setattr(cuda_libs, "_probe_cache", {"cublas": True, "cudnn": True})
    assert cuda_libs.cuda_usable() is False
