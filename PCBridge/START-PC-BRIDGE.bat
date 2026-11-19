@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js 18 or newer is required. Install it from https://nodejs.org/
  pause
  exit /b 1
)
echo Starting APK Sandbox PC Bridge...
node server.js
echo.
echo Server stopped.
pause
