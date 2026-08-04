@echo off
cd /d "%~dp0"
taskkill /F /IM gomusic.exe >nul 2>&1
echo Building...
D:\app-dev\flutter\bin\flutter.bat build windows
if %errorlevel% neq 0 (
    echo Build failed!
    pause
    exit /b %errorlevel%
)
echo Starting...
start "" "build\windows\x64\runner\Release\gomusic.exe"
