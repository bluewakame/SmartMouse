import SwiftUI

struct TutorialView: View {
    let onConnect: (String) -> Void
    let onFinish: () -> Void
    @State private var page = 0
    @State private var showingQRScanner = false

    private let accent = Color(red: 0.20, green: 0.86, blue: 0.62)
    private let pages = [
        TutorialPage(
            image: "TutorialWelcome",
            eyebrow: "SMARTMOUSE",
            title: "iPhoneをマウスに",
            message: "iPhoneとWindows PCを同じWi‑Fiにつなげば、マウスやキーボードが使えないときもPCを操作できます。"
        ),
        TutorialPage(
            image: "TutorialReceiver",
            eyebrow: "WINDOWS PC",
            title: "受信機を開く",
            message: "WindowsでSmartMouseReceiver.exeを開きます。初回だけファイアウォールの通信を許可してください。"
        ),
        TutorialPage(
            image: "TutorialQR",
            eyebrow: "かんたん接続",
            title: "QRコードを読み取る",
            message: "Windowsに表示されたQRコードへカメラを向けるだけで、自動的に接続します。",
            showsScannerButton: true
        ),
        TutorialPage(
            image: "TutorialGestures",
            eyebrow: "基本操作",
            title: "指先でPCを操作",
            message: "なぞって移動、1本指でタップ、2本指で右クリック。右端のバーでは上下にスクロールできます。"
        )
    ]

    var body: some View {
        ZStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    pageView(item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("閉じる", action: onFinish)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? accent : Color.white.opacity(0.38))
                            .frame(width: index == page ? 24 : 7, height: 7)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: page)
                .padding(.bottom, 10)

                HStack(spacing: 8) {
                    if page > 0 {
                        Button("戻る") { withAnimation { page -= 1 } }
                            .buttonStyle(CompactTutorialButton(primary: false, accent: accent))
                    }
                    Button(page == pages.count - 1 ? "使い始める" : "次へ") {
                        if page == pages.count - 1 {
                            onFinish()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(CompactTutorialButton(primary: true, accent: accent))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black)
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showingQRScanner) {
            QRScannerView { result in
                showingQRScanner = false
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

    private func pageView(_ item: TutorialPage) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Image(item.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.eyebrow)
                        .font(.caption.weight(.heavy))
                        .tracking(1.6)
                        .foregroundStyle(accent)
                    Text(item.title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.75)
                    Text(item.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    if item.showsScannerButton {
                        Button {
                            showingQRScanner = true
                        } label: {
                            Label("今すぐQRコードを読む", systemImage: "qrcode.viewfinder")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, item.showsScannerButton ? 116 : 104)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct TutorialPage {
    let image: String
    let eyebrow: String
    let title: String
    let message: String
    var showsScannerButton = false
}

private struct CompactTutorialButton: ButtonStyle {
    let primary: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(primary ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                primary ? accent.opacity(configuration.isPressed ? 0.72 : 1) : Color.black.opacity(0.56),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2))
                }
            }
    }
}
