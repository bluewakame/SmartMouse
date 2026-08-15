# SmartMouse iPhone MVP

SwiftUI製の最小SmartMouseクライアントです。既存Windows ReceiverのWebSocketへ接続し、画面上のドラッグを相対カーソル移動として送信します。

## 実行

1. Windowsで既存の `main.py` を起動します。
2. `SmartMouse.xcodeproj` をXcodeで開きます。
3. Targetの Signing & Capabilities で自分のTeamを選択します。
4. iPhoneをWindows PCと同じWi-Fiへ接続し、実機でアプリを実行します。
5. ReceiverのIP（例: `192.168.1.10:8000`）を入力して「接続」を押します。
6. 初回のローカルネットワーク許可を承認し、トラックパッド領域をドラッグします。

送信JSONは既存仕様の `{"type":"move","dx":数値,"dy":数値}` です。入力値は `ws://` を省略でき、ポート未指定時は `8000`、パス未指定時は `/ws` を補います。

このMVPはLAN内の `ws://` 接続用です。インターネットへReceiverを公開しないでください。

## 操作

- 1本指ドラッグ: カーソル移動
- 1本指タップ: 左クリック
- 1本指ダブルタップ: ダブルクリック
- 2本指タップ: 右クリック
- 2本指で上下にドラッグ: スクロール
- 長押ししてドラッグ: 左ボタンを押したまま移動
- 右端のスクロールバー: スクロール
- Grab / Drop: 左ボタンの押下状態を固定／解除
- Copy / Paste: Windows側でコピー／貼り付け
- Send: 入力文字をWindowsへ貼り付け
- Search: 入力文字を貼り付けてEnter
- ⌫: 入力欄を削除。空の場合はWindowsへBackspaceを送信
- 亀〜兎のスライダー: カーソル感度を0.5〜3.0倍に調整

Receiverの自動検出を使う場合は、`WindowsReceiverAddOn`のファイルと手順を既存Receiverへ追加してください。
