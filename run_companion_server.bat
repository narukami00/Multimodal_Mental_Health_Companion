@echo off
title Solace Companion Server (Tailscale)
echo ========================================================
echo   SOLACE COMPANION SERVER (Tailscale Edition)
echo ========================================================
echo   Tailscale IP: 100.88.46.59
echo   MagicDNS:     desktop-cdej4vj.tailc05ab0.ts.net
echo   Port:         8000
echo   WebSocket:    ws://100.88.46.59:8000/ws/v1/session
echo ========================================================
echo   Status: Ready for wireless connections from phone!
echo   (No USB cable or shared Wi-Fi network required)
echo ========================================================
echo.
cd /d "%~dp0companion_server"
python -m uvicorn main:app --host 0.0.0.0 --port 8000
pause
