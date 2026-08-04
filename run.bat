@echo off
cd /d "%~dp0"
taskkill /F /IM gomusic.exe >nul 2>&1
start "" "build\windows\x64\runner\Release\gomusic.exe"
