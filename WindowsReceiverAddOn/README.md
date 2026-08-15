# Receiver自動検出アドオン

1. Receiver一式を `C:\SmartMouse` に置きます。
2. `bonjour_main.py`、`requirements-addon.txt`、`start_smartmouse.bat`を既存の `main.py` と同じフォルダーへコピーします。
3. 初回だけ、そのフォルダーで `pip install -r requirements.txt -r requirements-addon.txt` を実行します。
4. 以後は `start_smartmouse.bat`をダブルクリックして起動できます。

マウスが使えない場合は、キーボードで `Windows + R`を押し、`C:\SmartMouse\start_smartmouse.bat`と入力してEnterを押します。

iPhoneアプリは同じLAN上のReceiverを検出すると、IPアドレスを入力せずに自動接続します。WindowsファイアウォールでPythonのプライベートネットワーク通信を許可してください。
