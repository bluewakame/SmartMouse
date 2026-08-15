# SmartMouse Emergency Mouse Keyboard

iPhoneをWindows PCの緊急用マウス・キーボードとして使うためのWindows側受信機です。
PC側でこのReceiverを起動し、同じWi-Fi/LAN上のiPhoneからSmartMouseアプリで接続します。

## 対象環境

- Windows 10 / Windows 11
- Python 3.11以上（配布exeを使う場合は不要）
- SmartMouse iPhoneアプリ（`SmartMouse.xcodeproj`）

ReceiverはWebSocket（`/ws`）とヘルスチェック（`/health`）のみを提供します。
ブラウザ用の操作画面は持ちません。

## 配布用exeを作成する

Windows 10 / 11上で `build_exe.bat` をダブルクリックすると、専用のビルド環境を作成して
`dist\SmartMouseReceiver.exe` を生成します。Pythonが入っていないPCにも、このexe単体を配布できます。

ビルドにはPython 3.11以上とインターネット接続が必要です。生成物はビルドしたWindowsと同じ
CPUアーキテクチャ向けになるため、一般配布用には64 bit版Windows上でビルドしてください。

配布先では `SmartMouseReceiver.exe` をダブルクリックして起動します。初回起動時に
Windows Defender Firewallの確認が表示されたら「プライベート ネットワーク」を許可してください。
通常画面に表示されるQRコードをiPhoneアプリで読み取ります。画面を閉じると
タスクトレイへ収納され、黒いコンソール画面は表示されません。

配布ZIPを作る場合は、exeのビルド後にPowerShellで次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\package_release.ps1 -Version 0.4.1
```

`release\SmartMouseReceiver-v0.4.1.zip` に、QR接続案内、バージョン、
警告の出ないSHA-256チェックサムを含む配布物が生成されます。

> Windows向けexeはWindows上でのみビルドできます。また、署名なしのexeではSmartScreenの
> 警告が表示される場合があります。一般公開する場合はコード署名を推奨します。

## インストーラーを作成する

WindowsへInno Setup 6をインストールし、exeのビルド後に次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\build_installer.ps1
```

`installer\SmartMouseReceiver-Setup-v0.4.1.exe` が生成されます。インストーラーは
ショートカット、自動起動、プライベートネットワーク用ファイアウォール規則、
アンインストールに対応します。

QRコードにはReceiver起動ごとに変わる一時認証情報が含まれます。未認証の端末から
WebSocketへ接続しても、マウスやキーボードを操作できません。

## インストール

Pythonから直接起動する場合のみ、以下を実行します。配布されたexeの実行には不要です。

```bash
pip install -r requirements.txt -r requirements-addon.txt
```

## 起動

```bash
python receiver_gui.py
```

起動すると、PCのLAN内IPv4アドレスを含んだQRコードが通常画面に表示されます。

## iPhone接続

1. Windows PCとiPhoneを同じWi-Fi/LANへ接続します。
2. Receiver画面のQRコードを、SmartMouse iPhoneアプリで読み取ります。
3. アプリ上部の表示が `接続済み` になったら操作できます。

同じLAN上であれば、アプリはBonjour（`_smartmouse._tcp`）でReceiverを自動検出して接続します。

> ペアリングトークンはReceiverの起動ごとに変わります。Receiverを再起動したら、
> アプリでQRコードを読み直すか、自動検出から選び直してください。
> 古いトークンのままでは、WebSocketが `1008` で切断されます。

## 操作

- 画面を1本指でなぞる: カーソル移動
- トラックパッド右端のスクロールバーを上下にドラッグ: スクロール
- 画面を1本指で短くタップ: 左クリック
- 画面を2本指で短くタップ: 右クリック
- 画面を素早く2回タップ: ダブルクリック
- 画面を長押ししてから移動: ドラッグ
- `つかむ`: クリックを押したままにする。カーソル移動後にもう一度押して離す
- `コピー`: 選択中の文字列をPC側でコピー
- `貼り付け`: PC側クリップボードを貼り付け
- `送信`: iPhoneで入力・変換した文字をPCへ貼り付け
- `エンター`: PCへEnterを送信
- `⌫`: 入力欄の文字を削除。空の時はPCへBackspace
- `全解除`: 押しっぱなしになったマウスボタンや修飾キーをPC側で解放

基本はiPhone側でいつも通り日本語入力し、バックスペースや変換もiPhoneキーボード上で済ませてから `送信` を使います。

## セキュリティ

LAN内専用です。サーバーは `0.0.0.0:8000` で待ち受けますが、ルーターやファイアウォールでインターネットに公開しないでください。

WebSocketの接続には、Receiver起動ごとに生成される32桁のペアリングトークンが必要です
（`receiver_protocol.py`）。トークンを持たない接続は、操作コマンドを受け付ける前に切断されます。

## トラブルシューティング

- iPhoneから接続できない場合は、WindowsファイアウォールでPythonの通信が許可されているか確認してください。
- PCとiPhoneが同じWi-Fiにいるか確認してください。
- 到達性の確認は、iPhoneのSafariで `http://<PCのIP>:8000/health` を開くのが確実です。
  `{"status":"ready","version":...,"protocol":...}` が返れば、経路とReceiverは正常です。
- アプリが「Receiverの更新が必要です」と表示する場合は、そこに出ているプロトコル番号を確認してください。
  配布パッケージのフォルダー名のバージョンは、コード側の `APP_VERSION` とは独立しています。
  実際に動いているコードの値は `python -c "import main, receiver_protocol; print(main.APP_VERSION, receiver_protocol.PROTOCOL_VERSION)"` で確認できます。
- カーソルが画面左上に移動して止まる場合は、PyAutoGUIのフェイルセーフが働いている可能性があります。マウスを左上から離して再度操作してください。
- クリックやカーソル移動が効かない場合は、Receiver画面の「問題の記録を開く」からログを確認してください。
