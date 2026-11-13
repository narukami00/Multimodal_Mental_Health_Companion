@echo off
rem Companion server with the optional emotion cue. Start run_emotion_service.bat first (the call works without it).
cd /d "%~dp0"
set SOLACE_EMOTION=1
set SOLACE_EMOTION_URL=http://127.0.0.1:8766
python -m uvicorn main:app --host 0.0.0.0 --port 8010
