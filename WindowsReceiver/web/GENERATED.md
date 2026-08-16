# このフォルダは自動生成です

スマホのブラウザ用アプリ（[SmartMouse-WEB](https://github.com/bluewakame/SmartMouse-WEB)）の
ビルド結果です。Receiverが8000番で配信し、exeにもそのまま同梱されます。

更新するときは、SmartMouse-WEB 側でビルドして丸ごと差し替えてください。

```bash
cd ../SmartMouse-WEB
npm ci && npm run build
rm -rf ../SmartMouse/WindowsReceiver/web && mkdir -p ../SmartMouse/WindowsReceiver/web
cp -r dist/. ../SmartMouse/WindowsReceiver/web/
```

Windows（PowerShell）の場合:

```powershell
cd ..\SmartMouse-WEB
npm ci; npm run build
robocopy dist ..\SmartMouse\WindowsReceiver\web /MIR
```

このフォルダを直接編集しないでください。次のビルドで上書きされます。
