import SwiftUI

struct TutorialView: View {
    let onConnect: (String) -> Void
    let onFinish: () -> Void
    @State private var page = 0
    @State private var showingQRScanner = false

    private let accent = Color(red: 0.20, green: 0.86, blue: 0.62)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    mouseUnavailable.tag(1)
                    keyboardUnavailable.tag(2)
                    iphoneConnection.tag(3)
                    gestures.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Label("説明が続く場合は上にスワイプ", systemImage: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? accent : Color.secondary.opacity(0.35))
                            .frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: page)
                .padding(.top, 8)

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("戻る") { withAnimation { page -= 1 } }
                            .buttonStyle(SecondaryTutorialButton())
                    }
                    Button(page == 4 ? "使い始める" : "次へ") {
                        if page == 4 { onFinish() } else { withAnimation { page += 1 } }
                    }
                    .buttonStyle(PrimaryTutorialButton(color: accent))
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onFinish)
                }
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showingQRScanner) {
            QRScannerView { result in
                showingQRScanner = false
                // カメラ画面の終了とWebSocket接続を同時に行うと、
                // 初回のローカルネットワーク許可が背面で止まることがある。
                // カメラを完全に閉じてから接続し、メイン画面へ戻す。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onConnect(result)
                    onFinish()
                }
            } onCancel: {
                showingQRScanner = false
            }
            .ignoresSafeArea()
        }
    }

    private var welcome: some View {
        tutorialPage(
            icon: "iphone.and.arrow.forward",
            title: "SmartMouseへようこそ",
            message: "キーボードかマウスが使えないとき、iPhoneからWindows PCを操作できます。",
            rows: [
                ("wifi", "iPhoneとPCを同じWi‑Fiにつなぐ"),
                ("dot.radiowaves.left.and.right", "受信機を起動すると自動で接続"),
                ("lock.shield", "家庭や職場のLAN内だけで使用")
            ]
        )
    }

    private var mouseUnavailable: some View {
        tutorialPage(
            icon: "keyboard",
            title: "マウスが使えない場合",
            message: "Windowsキーボードだけで受信機を起動します。受信機一式は C:\\SmartMouse に置いてください。",
            rows: [
                ("1.circle.fill", "WindowsキーとRを同時に押す"),
                ("2.circle.fill", "C:\\SmartMouse\\start_smartmouse.bat と入力"),
                ("3.circle.fill", "Enterを押して起動する")
            ]
        )
    }

    private var keyboardUnavailable: some View {
        tutorialPage(
            icon: "computermouse",
            title: "キーボードが使えない場合",
            message: "Windowsのマウスだけで受信機を起動します。",
            rows: [
                ("1.circle.fill", "エクスプローラーでPCを開く"),
                ("2.circle.fill", "CドライブからSmartMouseを開く"),
                ("3.circle.fill", "start_smartmouse.batをダブルクリック")
            ]
        )
    }

    private var iphoneConnection: some View {
        VStack(spacing: 0) {
            tutorialPage(
                icon: "qrcode.viewfinder",
                title: "QRコードで接続",
                message: "Windowsに表示されたQRコードを読み取るだけで接続できます。",
                rows: [
                    ("1.circle.fill", "Windowsで受信機を起動"),
                    ("2.circle.fill", "下のボタンでQRコードを読み取る"),
                    ("3.circle.fill", "「接続済み」になれば準備完了")
                ]
            )
            Button("QRコードを読み取る") { showingQRScanner = true }
                .font(.headline).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(accent, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal).padding(.bottom, 8)
        }
    }

    private var gestures: some View {
        tutorialPage(
            icon: "hand.draw",
            title: "基本操作",
            message: "広いタッチ操作エリアをノートPCのタッチパッドと同じように使います。",
            rows: [
                ("hand.tap", "1本指でタップ：左クリック"),
                ("hand.tap.fill", "2本指でタップ：右クリック"),
                ("arrow.up.and.down", "右端のバー：スクロール"),
                ("hand.raised.fill", "つかむ／離す：ドラッグを固定")
            ]
        )
    }

    private func tutorialPage(icon: String, title: String, message: String,
                              rows: [(String, String)]) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.top, 28)
                Text(title).font(.title.bold()).multilineTextAlignment(.center)
                Text(message).font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                VStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Label(row.1, systemImage: row.0)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct PrimaryTutorialButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SecondaryTutorialButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
