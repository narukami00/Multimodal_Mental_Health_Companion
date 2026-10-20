@echo off
rem One-click start: emotion service (GPU) -> USB link to the phone -> companion server (STT + LLM + TTS) on port 8000.
rem Double-click it. Close the windows (or Ctrl+C here) to stop. Everything is local; nothing is sent anywhere.
setlocal
title Solace - starting
set ROOT=%~dp0
set EMO_DIR=F:\__Downloads\dataset\scripts\emotion_service
set EMO_PY=F:\__Downloads\envs\face\Scripts\python.exe
set EMO_URL=http://127.0.0.1:8766
set SOLACE_EMOTION=0
set SOLACE_EMOTION_URL=%EMO_URL%
rem "start_solace.bat face" also loads the camera emotion model (more GPU memory; for video journals and calls)
set EMOTION_FACE=0
set SOLACE_EMOTION_FACE=0
if /i "%~1"=="face" set EMOTION_FACE=1
if /i "%~1"=="face" set SOLACE_EMOTION_FACE=1

echo.
echo  [1/4] Emotion service (voice + text + camera emotion model)
if not exist "%EMO_PY%" goto emo_missing
rem -f: only a real success counts, so another program answering on this port (a 404) cannot pass for the service
curl -sf -m 2 %EMO_URL%/healthz >nul 2>&1
if not errorlevel 1 goto emo_ok
start "Solace emotion service" /min cmd /c "cd /d %EMO_DIR% && %EMO_PY% -m uvicorn emotion_api:app --host 127.0.0.1 --port 8766"
echo        loading models, about 50 seconds ...
set /a tries=0
:emo_wait
curl -sf -m 2 %EMO_URL%/healthz >nul 2>&1
if not errorlevel 1 goto emo_ok
set /a tries+=1
if %tries% geq 45 goto emo_late
ping -n 3 127.0.0.1 >nul
goto emo_wait
:emo_ok
echo        ready
set SOLACE_EMOTION=1
goto emo_done
:emo_late
echo        NOT ready after 90 s - continuing WITHOUT emotion (look at the "Solace emotion service" window)
goto emo_done
:emo_missing
echo        emotion environment not found - continuing without emotion
:emo_done

echo.
echo  [2/4] Language model (Qwen3.5-2B via llama.cpp)
set LLM_GGUF=F:\__Downloads\envs\llm_models\Qwen3.5-2B-Q4_K_M.gguf
set LLM_URL=http://127.0.0.1:8081
if not defined LLAMA_NGL set LLAMA_NGL=99
set LLAMA_EXE=
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "Get-ChildItem \"$env:USERPROFILE\.lmstudio\extensions\backends\" -Directory -Filter 'llama.cpp-win-x86_64-nvidia-cuda*' | Sort-Object { [version]($_.Name -replace '^.*-(\d+\.\d+\.\d+)$','$1') } | Select-Object -Last 1 | ForEach-Object { Join-Path $_.FullName 'llama-server.exe' }"`) do set LLAMA_EXE=%%p
if not exist "%LLM_GGUF%" goto llm_skip
if not exist "%LLAMA_EXE%" goto llm_skip
curl -sf -m 2 %LLM_URL%/health >nul 2>&1
if not errorlevel 1 goto llm_ok
rem LM Studio keeps the CUDA runtime DLLs in a shared "vendor" folder; llama-server needs it on the PATH
set "LLAMA_VENDOR=%USERPROFILE%\.lmstudio\extensions\backends\vendor\win-llama-cuda-vendor-v2"
start "Solace language model" /min cmd /c "set PATH=%LLAMA_VENDOR%;%PATH% && "%LLAMA_EXE%" -m "%LLM_GGUF%" -ngl %LLAMA_NGL% -c 4096 --host 127.0.0.1 --port 8081 --jinja"
echo        loading the model, up to 60 seconds ...
set /a tries=0
:llm_wait
curl -sf -m 2 %LLM_URL%/health >nul 2>&1
if not errorlevel 1 goto llm_ok
set /a tries+=1
if %tries% geq 30 goto llm_late
ping -n 3 127.0.0.1 >nul
goto llm_wait
:llm_ok
echo        ready
set SOLACE_LLAMACPP_URL=%LLM_URL%
goto llm_done
:llm_late
echo        NOT ready after 60 s - the built-in small model will be used instead
goto llm_done
:llm_skip
echo        model file or llama.cpp not found - using the built-in small model
:llm_done

echo.
echo  [3/4] Phone over USB
adb start-server >nul 2>&1
adb devices | findstr /r /c:"device$" >nul
if errorlevel 1 goto no_phone
adb reverse tcp:8000 tcp:8000 >nul 2>&1
echo        phone linked: it reaches this server at localhost:8000
rem keeps the link alive if the cable is replugged
start "Solace USB link" /min python "%ROOT%companion_server\adb_watchdog.py"
goto phone_done
:no_phone
echo        no phone found over USB (plug it in, USB debugging on). Tailscale / Wi-Fi still works.
:phone_done

echo.
echo  [4/4] Companion server on port 8000 (first start loads the models, about 30-60 s)
echo        health: http://127.0.0.1:8000/healthz     Tailscale: ws://100.88.46.59:8000/ws/v1/session
echo.
title Solace companion server
cd /d "%ROOT%companion_server"
python -m uvicorn main:app --host 0.0.0.0 --port 8000
echo.
echo Server stopped.
pause
