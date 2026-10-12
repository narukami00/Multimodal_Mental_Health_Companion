@echo off
rem Emotion service for the companion server (slice 1). Needs ~4.7 GB of GPU memory. Listens on 127.0.0.1 only.
cd /d F:\__Downloads\dataset\scripts\emotion_service
F:\__Downloads\envs\face\Scripts\python.exe -m uvicorn emotion_api:app --host 127.0.0.1 --port 8766
