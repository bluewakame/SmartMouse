# SmartMouse Emergency Mouse Keyboard

iPhone SafariをWindows PCの緊急用マウス・キーボードとして使うMVPです。
PC側でPythonサーバーを起動し、同じWi-Fi/LAN上のiPhoneからブラウザで操作します。

## 対象環境

- Windows 10 / Windows 11
- Python 3.11以上
- iPhone Safari

## 配布用exeを作成する

Windows 10 / 11上で `build_exe.bat` をダブルクリックすると、専用のビルド環境を作成して
`dist\SmartMouseReceiver.exe` を生成します。Pythonが入っていないPCにも、このexe単体を配布できます。

ビルドにはPython 3.11以上とインターネット接続が必要です。生成物はビルドしたWindowsと同じ
CPUアーキテクチャ向けになるため、一般配布用には64 bit版Windows上でビルドしてください。

配布先では `SmartMouseReceiver.exe` をダブルクリックして起動します。初回起動時に
Windows Defender Firewallの確認が表示されたら「プライベート ネットワーク」を許可してください。
コンソールに表示されるQRコードをiPhoneアプリで読み取るか、表示URLをSafariで開きます。
終了するときはコンソールで `Ctrl+C` を押すか、ウィンドウを閉じます。

配布ZIPを作る場合は、exeのビルド後にPowerShellで次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\package_release.ps1 -Version 0.1.0
```

`release\SmartMouseReceiver-v0.1.0.zip` に、QR接続案内、バージョン、
警告の出ないSHA-256チェックサムを含む配布物が生成されます。

> Windows向けexeはWindows上でのみビルドできます。また、署名なしのexeではSmartScreenの
> 警告が表示される場合があります。一般公開する場合はコード署名を推奨します。

## インストール

Pythonから直接起動する場合のみ、以下を実行します。配布されたexeの実行には不要です。

```bash
pip install -r requirements.txt
```

## 起動

```bash
python main.py
```

起動すると、PCのLAN内IPv4アドレスを使ったURLが表示されます。

```text
Open this URL on your iPhone Safari:
http://192.168.x.x:8000
```

## iPhone接続

1. Windows PCとiPhoneを同じWi-Fi/LANへ接続します。
2. PCで表示された `http://192.168.x.x:8000` をiPhone Safariで開きます。
3. 画面上部の表示が `Connected` になったら操作できます。

## 操作

- 画面を1本指でなぞる: カーソル移動
- トラックパッド右端のスクロールバーを上下にドラッグ: スクロール
- 画面を1本指で短くタップ: 左クリック
- 画面を2本指で短くタップ: 右クリック
- 画面を素早く2回タップ: ダブルクリック
- 画面を長押ししてから移動: ドラッグ
- `Grab`: クリックを押したままにする。カーソル移動後に `Drop` で離す
- `Copy`: 選択中の文字列をPC側でコピー。`Grab`中に押すと、離してからコピー
- `Paste`: PC側クリップボードを貼り付け
- `Send`: iPhoneで入力・変換した文字をPCへ貼り付け
- `Search`: iPhoneで入力・変換した文字をPCへ貼り付けてEnter
- `⌫`: 入力欄の文字を削除。空の時はPCへBackspace

基本はiPhone側でいつも通り日本語入力し、バックスペースや変換もiPhoneキーボード上で済ませてから `Send` または `Search` を使います。

## セキュリティ

このMVPはLAN内専用です。サーバーは `0.0.0.0:8000` で待ち受けますが、ルーターやファイアウォールでインターネットに公開しないでください。

## トラブルシューティング

- iPhoneから開けない場合は、WindowsファイアウォールでPythonの通信が許可されているか確認してください。
- PCとiPhoneが同じWi-Fiにいるか確認してください。
- カーソルが画面左上に移動して止まる場合は、PyAutoGUIのフェイルセーフが働いている可能性があります。マウスを左上から離して再度操作してください。
- クリックやカーソル移動が効かない場合は、PC側のターミナルログにエラーが出ていないか確認してください。
