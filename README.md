# SmartMouse iPhone MVP

SwiftUI製の最小SmartMouseクライアントです。既存Windows ReceiverのWebSocketへ接続し、画面上のドラッグを相対カーソル移動として送信します。

クライアントは2種類あります。用途に応じて選べます。

| クライアント | 入手方法 | 備考 |
| --- | --- | --- |
| **ブラウザ版** | Receiverが同梱・配信（インストール不要） | Receiver画面のQRを**標準のカメラ**で読むだけ。iPhone/Android両対応。ソースは [SmartMouse-WEB](https://github.com/bluewakame/SmartMouse-WEB) |
| iOSアプリ版 | このリポジトリをXcodeでビルド | Bonjour自動検出や触覚フィードバックに対応 |

QRコードは1つで両方に使えます（`http://<PCのIP>:8000/?token=…`。iOSアプリはこれを `ws://…/ws?token=…` に読み替えます）。

## Receiverの入手

Windows側の受信機は [Releases](https://github.com/bluewakame/SmartMouse/releases) から入手します。
ソースから動かす場合は [`WindowsReceiver/README.md`](WindowsReceiver/README.md) を参照してください。

アプリはReceiverがプロトコル `2` を返すことを要求します。プロトコル `1` の配布版
（`v0.1.0`）では、接続時に「Receiverの更新が必要です」と表示されて接続できません。
配布パッケージのファイル名のバージョンはコード側の `APP_VERSION` とは独立しているため、
名前だけでは判断できません。稼働中のReceiverの実際の値は次で確認できます。

```
http://<PCのIPアドレス>:8000/health
```

## 実行

1. Windowsで `SmartMouseReceiver.exe` を起動します。
2. `SmartMouse.xcodeproj` をXcodeで開きます。
3. Targetの Signing & Capabilities で自分のTeamを選択します。
4. iPhoneをWindows PCと同じWi-Fiへ接続し、実機でアプリを実行します。
5. Receiver画面のQRコードを読み取ります。初回のカメラとローカルネットワークの許可を承認します。
6. 「接続済み」と表示されたら、トラックパッド領域をドラッグします。

Receiverは起動ごとに変わる合言葉（token）を要求します（プロトコル `2`）。接続先は
`ws://192.168.1.10:8000/ws?token=…` の形式で、QRコード、Bonjour自動検出、Receiver画面の
表示のいずれかから取得します。合言葉なしのアドレスはReceiverに拒否されるため、アプリは
その場合QRコードの読み取りを案内します。

一度読み取った接続先は保存され、Receiverが起動したままならアプリ再起動時に自動で接続します。
Receiverを再起動して合言葉が変わった場合は、Bonjourで新しいReceiverを見つけ次第自動で繋ぎ直し、
見つからないときだけQRコードの読み取りを促します。

送信JSONは既存仕様の `{"type":"move","dx":数値,"dy":数値}` です。手入力の場合、`ws://` は省略でき、
ポート未指定時は `8000`、パス未指定時は `/ws` を補います（`?token=…` は必須）。

このMVPはLAN内の `ws://` 接続用です。インターネットへReceiverを公開しないでください。

## 操作

- 1本指ドラッグ: カーソル移動
- 1本指タップ: 左クリック
- 1本指ダブルタップ: ダブルクリック
- 2本指タップ: 右クリック
- 2本指で上下にドラッグ: スクロール
- 長押ししてドラッグ: 左ボタンを押したまま移動
- 右端のスクロールバー: スクロール
- つかむ／離す: 左ボタンの押下状態を固定／解除
- コピー／貼り付け: Windows側でコピー／貼り付け
- 送信: 入力文字をWindowsへ貼り付け
- エンター: 入力文字を貼り付けてEnter
- ⌫: 入力欄を削除。空の場合はWindowsへBackspaceを送信
- 亀〜兎のスライダー: カーソル感度を0.5〜3.0倍に調整

ReceiverはQR接続、自動検出、タスクトレイ常駐に対応しています。画面を閉じても
Windows右下のSmartMouseアイコンからQRコードを再表示できます。
