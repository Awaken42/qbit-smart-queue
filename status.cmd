@echo off
setlocal
cd /d "%~dp0"
title qBit Smart Queue Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0status.ps1"
echo.
pause
