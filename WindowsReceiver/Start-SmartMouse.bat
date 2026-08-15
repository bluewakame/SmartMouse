@echo off
setlocal
cd /d "%~dp0"
title SmartMouse Receiver

echo SmartMouse Receiverを起動しています...
echo ファイアウォールの確認では、プライベート ネットワークを許可してください。
echo 起動後はQRコード画面とタスクトレイアイコンから操作できます。
echo.

start "" SmartMouseReceiver.exe

echo.
echo SmartMouse Receiverを起動しました。
timeout /t 3 >nul
