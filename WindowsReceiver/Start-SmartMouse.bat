@echo off
setlocal
cd /d "%~dp0"
title SmartMouse Receiver

echo SmartMouse Receiverを起動しています...
echo ファイアウォールの確認では、プライベート ネットワークを許可してください。
echo 使用中はこのウィンドウを閉じないでください。
echo.

SmartMouseReceiver.exe

echo.
echo SmartMouse Receiverは終了しました。
echo エラーで終了した場合は、この画面のスクリーンショットを保存してください。
pause
