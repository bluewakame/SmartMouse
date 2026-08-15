@echo off
cd /d "%~dp0"
python bonjour_main.py
if errorlevel 1 (
  echo.
  echo SmartMouse could not start. Please check that Python and requirements are installed.
  pause
)
