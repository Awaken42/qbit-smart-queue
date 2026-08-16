@echo off
setlocal
cd /d "%~dp0"
title qBit Smart Queue Installer
echo.
echo Starting qBit Smart Queue installer...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -StartNow
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Installation returned error code %EXITCODE%.
  echo Please copy the error message when opening a GitHub issue.
) else (
  echo Installation finished.
)
echo.
pause
exit /b %EXITCODE%
