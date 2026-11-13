#!/usr/bin/env python3
"""Reproducible offline verification harness for Solace.

Runs model-free checks across repository consent migration scripts,
emotion_server unit tests, companion_server unit/auth/HTTP tests,
Flutter static analysis, and (by default) the Flutter test suite.
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass
class CheckResult:
    name: str
    status: str  # PASS | FAIL | SKIPPED
    duration_s: float
    detail: str = ""


def _resolve_bin(name: str) -> str:
    if platform.system() == "Windows":
        for ext in (".bat", ".cmd", ".exe"):
            found = shutil.which(f"{name}{ext}")
            if found:
                return found
    return shutil.which(name) or name


def _run(
    name: str,
    cmd: list[str],
    cwd: Path,
) -> CheckResult:
    print(f"\n=== [{name}] ({cwd.relative_to(ROOT) if cwd != ROOT else '.'}) ===")
    print("+", " ".join(cmd))
    t0 = time.monotonic()
    proc = subprocess.run(cmd, cwd=str(cwd))
    dt = time.monotonic() - t0
    status = "PASS" if proc.returncode == 0 else "FAIL"
    return CheckResult(name=name, status=status, duration_s=dt, detail=f"exit={proc.returncode}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-flutter-tests",
        action="store_true",
        help="Run flutter analyze but skip flutter test for a quick smoke check.",
    )
    parser.add_argument(
        "--verify-assets",
        action="store_true",
        help="Also run emotion_server/check_assets.py --verify-hashes --face.",
    )
    args = parser.parse_args()

    dart_bin = _resolve_bin("dart")
    flutter_bin = _resolve_bin("flutter")
    py_bin = sys.executable

    results: list[CheckResult] = []

    results.append(
        _run(
            "Emotion consent migration check",
            [dart_bin, "scripts/verify_emotion_consent.dart"],
            cwd=ROOT,
        )
    )

    results.append(
        _run(
            "Emotion server cue unit tests",
            [py_bin, "-m", "unittest", "discover", "-s", ".", "-p", "test_cue.py", "-v"],
            cwd=ROOT / "emotion_server",
        )
    )

    if args.verify_assets:
        results.append(
            _run(
                "Emotion server asset manifest check",
                [py_bin, "check_assets.py", "--verify-hashes", "--face"],
                cwd=ROOT / "emotion_server",
            )
        )
    else:
        results.append(
            CheckResult(
                name="Emotion server asset manifest check",
                status="SKIPPED",
                duration_s=0.0,
                detail="Pass --verify-assets when SOLACE_EMOTION_ARTIFACTS_DIR/MODELS_DIR are configured.",
            )
        )

    companion_tests = [
        "test_memory_prompt.py",
        "test_turn_detector.py",
        "test_session_logic.py",
        "test_conversation_memory.py",
        "test_tts_chunker.py",
        "test_journal_api.py",
        "test_auth_service.py",
        "test_auth_http.py",
        "test_llm_service.py",
        "test_emotion_health.py",
        "test_moment_extraction.py",
        "test_user_facts_and_scaling.py",
    ]
    results.append(
        _run(
            "Companion server unit, prompt & auth suites",
            [py_bin, "-m", "pytest", *companion_tests],
            cwd=ROOT / "companion_server",
        )
    )

    results.append(
        _run(
            "Flutter static analysis",
            [flutter_bin, "analyze"],
            cwd=ROOT / "mobile_application",
        )
    )

    if args.skip_flutter_tests:
        results.append(
            CheckResult(
                name="Flutter test suite",
                status="SKIPPED",
                duration_s=0.0,
                detail="Skipped via --skip-flutter-tests.",
            )
        )
    else:
        results.append(
            _run(
                "Flutter test suite",
                [flutter_bin, "test"],
                cwd=ROOT / "mobile_application",
            )
        )

    print("\n================ VERIFICATION SUMMARY ================")
    failed = 0
    for r in results:
        if r.status == "FAIL":
            failed += 1
        note = f" ({r.detail})" if r.detail else ""
        print(f"[{r.status:7s}] {r.name:<48s} {r.duration_s:6.1f}s{note}")

    return 1 if failed > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
