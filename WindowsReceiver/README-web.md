# SmartMouse Emergency Mouse Keyboard

iPhone SafariをWindows PCの緊急用マウス・キーボードとして使うMVPです。
PC側でPythonサーバーを起動し、同じWi-Fi/LAN上のiPhoneからブラウザで操作します。

## 対象環境

- Windows 10 / Windows 11
- Python 3.11以上
- iPhone Safari

## インストール

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
