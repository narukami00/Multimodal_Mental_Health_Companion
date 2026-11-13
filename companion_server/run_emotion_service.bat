@echo off
rem Reference emotion service for the companion server. Listens on 127.0.0.1 only.
cd /d "%~dp0..\emotion_server"
if not defined SOLACE_EMOTION_PYTHON (
    if exist ".venv\Scripts\python.exe" (
        set "SOLACE_EMOTION_PYTHON=.venv\Scripts\python.exe"
    ) else (
        set "SOLACE_EMOTION_PYTHON=python"
    )
)
"%SOLACE_EMOTION_PYTHON%" -m uvicorn emotion_api:app --host 127.0.0.1 --port 8766
