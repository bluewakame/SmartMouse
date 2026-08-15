@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if errorlevel 1 (
  echo Python launcher "py" was not found. Install Python 3.11 or later first.
  exit /b 1
)

if not exist ".venv-build\Scripts\python.exe" (
  echo Creating build environment...
  py -3 -m venv .venv-build
  if errorlevel 1 exit /b 1
)

echo Installing build dependencies...
call ".venv-build\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 exit /b 1
call ".venv-build\Scripts\python.exe" -m pip install -r requirements-build.txt
if errorlevel 1 exit /b 1

echo Building SmartMouseReceiver.exe...
call ".venv-build\Scripts\python.exe" -m PyInstaller --noconfirm --clean SmartMouseReceiver.spec
if errorlevel 1 exit /b 1

echo.
echo Build complete: %CD%\dist\SmartMouseReceiver.exe
endlocal
