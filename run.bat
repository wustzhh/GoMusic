@echo off
cd /d "%~dp0"
echo Starting GoMusic...
start "" "build\windows\x64\runner\Release\gomusic.exe"
