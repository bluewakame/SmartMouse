# このフォルダは自動生成です

スマホのブラウザ用アプリ（[SmartMouse-WEB](https://github.com/bluewakame/SmartMouse-WEB)）の
ビルド結果です。Receiverが8000番で配信し、exeにもそのまま同梱されます。

更新するときは、SmartMouse-WEB 側でビルドして丸ごと差し替えてください。

```bash
cd ../SmartMouse-WEB
npm ci && npm run build
# assets/ は毎回ファイル名が変わるので、消してから入れ直す。
# このGENERATED.mdはdistに無いため、web/ ごと消すと巻き添えで消える。
rm -rf ../SmartMouse/WindowsReceiver/web/assets
cp -r dist/. ../SmartMouse/WindowsReceiver/web/
```

Windows（PowerShell）の場合:

```powershell
cd ..\SmartMouse-WEB
npm ci; npm run build
# /MIR はミラーなので、distに無いGENERATED.mdを消してしまう。除外して守る。
robocopy dist ..\SmartMouse\WindowsReceiver\web /MIR /XF GENERATED.md
```

このフォルダを直接編集しないでください。次のビルドで上書きされます。
