# SmartMouse Emergency Mouse Keyboard

iPhoneをWindows PCの緊急用マウス・キーボードとして使うためのWindows側受信機です。
PC側でこのReceiverを起動し、同じWi-Fi/LAN上のiPhoneからSmartMouseアプリで接続します。

## 対象環境

- Windows 10 / Windows 11
- Python 3.11以上（配布exeを使う場合は不要）
- SmartMouse iPhoneアプリ（`SmartMouse.xcodeproj`）

Receiverは8000番で、スマホのブラウザ用アプリ（`/`）、操作用のWebSocket（`/ws`）、
ヘルスチェック（`/health`）の3つを提供します。iPhoneアプリが無くてもブラウザだけで使えます。

ビルド済みの配布版は [Releases](https://github.com/bluewakame/SmartMouse/releases) にあります。
以下は、ソースからビルド・実行する場合の手順です。

## Webアプリを同梱する

`web/` には [SmartMouse-WEB](https://github.com/bluewakame/SmartMouse-WEB) のビルド結果が入っていて、
PyInstallerがexeへそのまま同梱します（実行時は `_internal/web`）。
Webアプリ側を更新したら、次の手順で差し替えてからexeをビルドします。

```powershell
cd ..\SmartMouse-WEB
npm ci; npm run build
robocopy dist ..\SmartMouse\WindowsReceiver\web /MIR
```

`web/index.html` が無い場合、exeはWebアプリ無しでビルドされ、`/` は404になります
（`/ws` と `/health` は動くのでiPhoneアプリからは使えます）。

## 配布用exeを作成する

Windows 10 / 11上で `build_exe.bat` をダブルクリックすると、専用のビルド環境を作成して
`dist\SmartMouseReceiver\` フォルダーを生成します。Pythonが入っていないPCへも、この
**フォルダーごと** 配布できます。

```text
dist\SmartMouseReceiver\
├─ SmartMouseReceiver.exe   ← これを起動する
└─ _internal\               ← Python本体と依存ライブラリ
```

`SmartMouseReceiver.exe` だけを抜き出しても起動しません。必ず `_internal` と同じ場所に
置いたまま配布・移動してください。

ビルドにはPython 3.11以上とインターネット接続が必要です。生成物はビルドしたWindowsと同じ
CPUアーキテクチャ向けになるため、一般配布用には64 bit版Windows上でビルドしてください。

配布先では `SmartMouseReceiver.exe` をダブルクリックして起動します。初回起動時に
Windows Defender Firewallの確認が表示されたら「プライベート ネットワーク」を許可してください。
通常画面に表示されるQRコードをiPhoneアプリで読み取ります。画面を閉じると
タスクトレイへ収納され、黒いコンソール画面は表示されません。

配布ZIPを作る場合は、exeのビルド後にPowerShellで次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\package_release.ps1 -Version 0.5.1
```

`release\SmartMouseReceiver-v0.5.1.zip` に、アプリ本体一式、QR接続案内、バージョン、
同梱ファイル全件のSHA-256チェックサムを含む配布物が生成されます。

コード署名する場合は、証明書の拇印を渡します。`-SignBundledBinaries` を付けると
`_internal` 内のDLL／PYDまで署名します（時間はかかりますが、より疑われにくくなります）。

```powershell
powershell -ExecutionPolicy Bypass -File .\package_release.ps1 -Version 0.5.1 -CertificateThumbprint <拇印>
```

> Windows向けexeはWindows上でのみビルドできます。また、署名なしのexeではSmartScreenの
> 警告が表示される場合があります。一般公開する場合はコード署名を推奨します。

## Defender／SmartScreenの誤検知を減らす方針

このReceiverはマウスとキーボードを外部からの入力で操作するため、振る舞いだけを見ると
遠隔操作ツールと区別が付きにくく、もともと誤検知されやすい部類です。そのぶん、
「怪しく見える作り」を避けることをビルド方針として固定しています。

やっていること。

- **onedirでビルドする。** `--onefile` は起動のたびに自分自身を `%TEMP%` へ展開して実行する
  ため、ドロッパー型マルウェアと同じ挙動になります。`SmartMouseReceiver.spec` は
  `COLLECT` を使ったonedir構成です。
- **UPX圧縮をしない。** 実行ファイルの圧縮・パックはヒューリスティックの主要な減点要素です。
  `EXE` と `COLLECT` の両方で `upx=False` を指定しています。
- **strip・難読化・暗号化をしない。**
- **バージョン情報リソースとアイコンを埋め込む。** 発行元も版数もないexeは、それだけで
  SmartScreenの評価が下がります。バージョンは `main.py` の `APP_VERSION` から自動生成します。
- **不要な同梱物を減らす。** pytestやpipなど開発用パッケージはspecの `excludes` で除外します。
- **正式配布ではコード署名する。** EV／OV証明書での署名がSmartScreen警告への唯一の正攻法です。
  個人でも使える選択肢としては[Azure Trusted Signing](https://learn.microsoft.com/azure/trusted-signing/)
  （月額制。本人確認が必要）があり、GitHub Actionsから署名できます。
  **署名しない限り、初回のSmartScreen警告は消せません。**
- **GitHub Actionsで公開ビルドする。** 誰でも同じ手順を再現でき、
  `actions/attest-build-provenance` の証明が付くため、配布物の出所を確認できます。

やらないこと。

- Defenderの無効化、除外リストへの自動追加、セキュリティ設定の変更
- 難読化やパッカーによる検知回避
- 自己更新、自己展開、EXEから別EXEを取り出しての実行
- 不要な子プロセスの生成（Uvicornは同一プロセス内で `uvicorn.Server` として起動します）

それでも誤検知された場合は、検知回避を実装せず
[Microsoft Security Intelligence](https://www.microsoft.com/wdsi/filesubmission) へ
誤検知（false positive）として提出してください。判定はファイルのハッシュ単位なので、
提出したビルドと配布するビルドは同一物である必要があります（`CHECKSUMS-SHA256.txt` を利用）。

なお、Receiver画面の「Windowsへのサインイン時に自動で起動」は
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` へ登録します。未署名exeによる
自動起動登録は監視対象の挙動なので、警告が出た場合はこのチェックを外してください。

## インストーラーを作成する

WindowsへInno Setup 6をインストールし、exeのビルド後に次を実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\build_installer.ps1
```

`installer\SmartMouseReceiver-Setup-v0.5.1.exe` が生成されます。インストーラーは
ショートカット、自動起動、プライベートネットワーク用ファイアウォール規則、
アンインストールに対応します。

QRコードにはReceiver起動ごとに変わる一時認証情報が含まれます。未認証の端末から
WebSocketへ接続しても、マウスやキーボードを操作できません。

## 配布物を使う（いちばん簡単）

[Releases](https://github.com/bluewakame/SmartMouse/releases) から
`SmartMouseReceiver-vX.Y.Z.zip` をダウンロードし、展開して
`SmartMouseReceiver.exe` を実行します。Python も Node.js も要りません。

> 未署名のため、初回起動時にSmartScreenが「WindowsによってPCが保護されました」と
> 出ることがあります。「詳細情報」→「実行」で起動できます。詳しくは
> 「Defender／SmartScreenの誤検知を減らす方針」を参照してください。

exeはGitHub Actions（`.github/workflows/receiver-release.yml`）がWindows上でビルドし、
ビルド元を証明する[provenance](https://docs.github.com/actions/security-guides/using-artifact-attestations)
を付けて公開します。手元で作る場合は「配布用exeを作成する」を参照してください。

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

## スマホから接続する

Receiverは8000番で次の3つをまとめて提供します。

| 経路 | 用途 |
| --- | --- |
| `/` | スマホのブラウザ用アプリ（[SmartMouse-WEB](https://github.com/bluewakame/SmartMouse-WEB) のビルド結果を `web/` から配信） |
| `/ws` | 操作用のWebSocket（合言葉が必要） |
| `/health` | 稼働確認と遅延計測 |

### ブラウザで使う（アプリのインストール不要）

1. Windows PCとスマホを同じWi-Fi/LANへ接続します。
2. Receiver画面のQRコードを、**スマホの標準カメラアプリ**で読み取ります。
3. ブラウザが開き、そのまま `接続済み` になります。

QRコードには `http://<PCのIP>:8000/?token=<合言葉>` が入っています。
ページとWebSocketが同じオリジンなので、ブラウザの混在コンテンツ制限に引っかからず、
配信用の別サーバーもポート開放も要りません。

### iPhoneアプリで使う

同じQRコードをSmartMouse iPhoneアプリで読み取っても接続できます。
アプリは `http://…?token=…` を `ws://…/ws?token=…` に読み替えるため、QRコードは1つで足ります。

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

### 想定している使い方（脅威モデル）

**通信は暗号化されていません。** Receiverは `ws://` の平文で待ち受けます。
想定しているのは **「自分の家のWi-Fiで、自分のPCを操作する」** ことだけです。

| | |
| --- | --- |
| **使ってよい** | 自宅など、繋いでいる人を自分で把握できるWi-Fi |
| **使わないほうがよい** | 社内・学校・カフェ・ホテル・空港・寮などの共有Wi-Fi |
| **送ってはいけないもの** | パスワード、クレジットカード番号、その他の秘密（アプリの「文字入力 → 送信」はそのまま平文で流れます） |

ペアリングトークンは32桁の16進数（128 bit）なので推測は不可能ですが、**平文で流れるため傍受はされます**。
WPA2パーソナルのように接続パスワードを共有するWi-Fiでは、同じネットワークの参加者が通信を復号できます。
そしてトークンを得た相手は、マウス・キーボード・クリップボードを自由に操作できます。
これは実質的に、PCの前に座っているのと同じことができるという意味です。

`wss://`（暗号化あり）に対応していないのは、自己署名証明書を使うことになり、
ブラウザの証明書警告という別の壁が立つためです。既知の課題として残しています。

### 実装している防御

- **LAN内専用。** サーバーは `0.0.0.0:8000` で待ち受けますが、ルーターやファイアウォールで
  インターネットに公開しないでください。
- **ペアリングトークン。** WebSocketの接続には、Receiver起動ごとに生成される32桁の
  トークンが必要です（`receiver_protocol.py`）。照合は `secrets.compare_digest` で行い、
  トークンを持たない接続は操作コマンドを受け付ける前に切断されます。
- **トークンはログに残さない。** Uvicornのアクセスログはリクエスト行をクエリ文字列ごと
  出力するため、そのままでは接続のたびにトークンが平文でログに残ります。`log_filters.py` が
  これを `token=<redacted>` に伏せます（起動時バナーのURL表示は、読み取ってもらうために
  意図して出しているので伏せません）。
- **切断時の状態解放。** 通信が切れた瞬間にドラッグ中でも、`release_all_inputs()` が
  押しっぱなしのボタンと修飾キーをすべて解放します。

### 使い終わったら

**Receiverを終了してください。** トークンは起動するたびに新しくなり、古いトークンは無効になります。
これが最も確実な遮断方法です。

QRコードにはトークンが含まれます。画面共有や配信の最中に表示したままにしないでください。

## トラブルシューティング

- **標準のカメラでQRを読むと「使用可能なデータが見つかりません」と出る場合**、
  そのQRには `ws://` が入っています。iOSのカメラは `ws:` を開けるアプリを持たないため、
  読み取り自体は成功しても、開く先が無いと言って終わります。次のどれかで解決します。
  - v0.5.0以降の `SmartMouseReceiver.exe`（または `python receiver_gui.py`）で起動し直す。
    こちらのQRは `http://<PCのIP>:8000/?token=…` なので、標準のカメラから直接開けます。
  - iPhoneアプリを使う場合は、標準カメラではなくアプリ内の「QRコードを読み取って接続」から読む。
    アプリは `ws://` を解釈できます。
  - Receiver画面の「手入力用」に出ている `ws://…` を、アプリの設定へ直接入力する。
- iPhoneから接続できない場合は、WindowsファイアウォールでPythonの通信が許可されているか確認してください。
- PCとiPhoneが同じWi-Fiにいるか確認してください。
- 到達性の確認は、iPhoneのSafariで `http://<PCのIP>:8000/health` を開くのが確実です。
  `{"status":"ready","version":...,"protocol":...}` が返れば、経路とReceiverは正常です。
- アプリが「Receiverの更新が必要です」と表示する場合は、そこに出ているプロトコル番号を確認してください。
  配布パッケージのフォルダー名のバージョンは、コード側の `APP_VERSION` とは独立しています。
  実際に動いているコードの値は `python -c "import main, receiver_protocol; print(main.APP_VERSION, receiver_protocol.PROTOCOL_VERSION)"` で確認できます。
- カーソルが画面左上に移動して止まる場合は、PyAutoGUIのフェイルセーフが働いている可能性があります。マウスを左上から離して再度操作してください。
- クリックやカーソル移動が効かない場合は、Receiver画面の「問題の記録を開く」からログを確認してください。
