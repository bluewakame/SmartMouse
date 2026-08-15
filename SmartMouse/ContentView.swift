import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var client = MouseWebSocketClient()
    @StateObject private var discovery = ReceiverDiscovery()
    @AppStorage("receiverAddress") private var receiverAddress = "192.168.1.2:8000"
    @AppStorage("pointerSensitivity") private var sensitivity = 1.5
    @AppStorage("tutorialVersion") private var tutorialVersion = 0
    @State private var inputText = ""
    @State private var dragLocked = false
    @State private var showingSettings = false
    @State private var scrollOffset: CGFloat = 0
    @State private var edgeScrollTimer: Timer?
    @State private var edgeScrollDirection = 0.0
    @State private var showingTutorial = false
    @State private var showingQRScanner = false
    @State private var didPresentStartupFlow = false
    @FocusState private var inputFocused: Bool

    private let accent = Color(red: 0.20, green: 0.86, blue: 0.62)
    private let panel = Color(red: 0.095, green: 0.105, blue: 0.11)
    private let control = Color(red: 0.16, green: 0.17, blue: 0.18)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.045, green: 0.05, blue: 0.055).ignoresSafeArea()
                VStack(spacing: 0) {
                    touchpadArea(topInset: geometry.safeAreaInsets.top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { settingsSheet }
        .fullScreenCover(isPresented: $showingTutorial) {
            TutorialView(onConnect: connectFromQRCode) {
                tutorialVersion = 4
                showingTutorial = false
            }
        }
        .fullScreenCover(isPresented: $showingQRScanner) {
            QRScannerView { result in
                showingQRScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    connectFromQRCode(result)
                }
            } onCancel: {
                showingQRScanner = false
            }
            .ignoresSafeArea()
        }
        .onAppear {
            discovery.start()
            guard !didPresentStartupFlow else { return }
            didPresentStartupFlow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if tutorialVersion < 4 {
                    showingTutorial = true
                } else if client.state != .connected {
                    showingQRScanner = true
                }
            }
        }
        .onDisappear {
            discovery.stop()
            stopEdgeScroll()
            if dragLocked { client.sendMouseUp() }
            client.disconnect()
        }
        .onReceive(discovery.$receivers) { receivers in
            guard client.state == .disconnected, let receiver = receivers.first else { return }
            showingQRScanner = false
            receiverAddress = receiver.address
            client.connect(to: receiver.address)
        }
        .onChange(of: client.state) { _, state in
            if state != .connected, dragLocked {
                dragLocked = false
            }
            if state == .connected {
                UIAccessibility.post(notification: .announcement, argument: "Windows PCへ接続しました")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func touchpadArea(topInset: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: dragLocked
                    ? [Color(red: 0.07, green: 0.16, blue: 0.12), Color(red: 0.06, green: 0.10, blue: 0.09)]
                    : [panel, Color(red: 0.075, green: 0.08, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            TrackpadView(
                isEnabled: client.state == .connected, isDragLocked: dragLocked,
                onMove: {
                    dismissKeyboard()
                    client.sendMove(dx: $0.width * sensitivity, dy: $0.height * sensitivity)
                },
                onScroll: {
                    dismissKeyboard()
                    client.sendScroll(amount: -$0 / 8)
                },
                onTap: {
                    dismissKeyboard()
                    client.sendClick()
                },
                onDoubleTap: {
                    dismissKeyboard()
                    client.sendDoubleClick()
                },
                onRightTap: {
                    dismissKeyboard()
                    client.sendRightClick()
                },
                onDragBegin: {
                    dismissKeyboard()
                    client.sendMouseDown()
                },
                onDragEnd: client.sendMouseUp
            )

            VStack {
                header
                    .padding(.top, topInset)
                if client.state != .connected {
                    connectionBanner
                        .padding(.trailing, 40)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                keyboardPanel
                    .padding(.trailing, 40)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: dragLocked ? "hand.point.up.left.fill" : "hand.draw.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(dragLocked ? accent : Color.white.opacity(0.88))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dragLocked ? "ドラッグ中" : "タッチ操作エリア")
                                .font(.headline.weight(.bold)).foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("画面を指でなぞって")
                                Text("カーソルを動かします")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }

                    HStack(spacing: 8) {
                        gestureHint(icon: "hand.tap", text: "1本指：タップ")
                        gestureHint(icon: "hand.tap.fill", text: "2本指：右クリック")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.horizontal, 14)
                .padding(.trailing, 58)
                .allowsHitTesting(false)
                Spacer()
                actionButtons
            }
            .padding(.horizontal, 8)

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(dragLocked ? 0.22 : 0.09), lineWidth: 1.5)
                .padding(.horizontal, 8)
                .padding(.top, 76)
                .padding(.bottom, 76)
                .allowsHitTesting(false)

            HStack { Spacer(); scrollRail }
                .padding(.trailing, 2)
                .padding(.top, 2)
                .padding(.bottom, 2)
        }
        .frame(maxHeight: .infinity)
        .clipped()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SmartMouse")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("緊急用マウス・キーボード")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Button { showingSettings = true } label: {
                HStack(spacing: 6) {
                    Circle().fill(client.state == .connected ? accent : .red).frame(width: 8, height: 8)
                    Text(client.state == .connected ? "接続済み" : "未接続")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(client.state == .connected ? Color.white.opacity(0.82) : .secondary)
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            .fixedSize()
            .accessibilityLabel("接続設定")
            .accessibilityValue(client.state.label)
            .accessibilityHint("接続先の設定とチュートリアルを開きます")
        }
        .padding(.top, 6)
        .padding(.trailing, 40)
    }

    private var connectionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if client.state == .connecting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text(connectionTitle)
                    .font(.caption.weight(.bold))
                    .lineLimit(2)
                Spacer(minLength: 4)
            }

            if !client.recoveryHint.isEmpty {
                Text(client.recoveryHint)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Button("再接続") { client.connect(to: receiverAddress) }
                    .disabled(client.state == .connecting)
                Button("QRを読む") { showingQRScanner = true }
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private var connectionTitle: String {
        if case .failed(let message) = client.state { return message }
        return client.state.label
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            controlButton("コピー", systemImage: "doc.on.doc") {
                if dragLocked {
                    dragLocked = false
                    client.sendMouseUp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { client.sendShortcut("copy") }
                } else { client.sendShortcut("copy") }
            }
            controlButton("貼り付け", systemImage: "doc.on.clipboard") { client.sendShortcut("paste") }
            ImmediateControlButton(
                title: dragLocked ? "離す" : "つかむ",
                systemImage: dragLocked ? "hand.raised.slash.fill" : "hand.raised.fill",
                active: dragLocked,
                accent: accent,
                control: control
            ) {
                dragLocked.toggle()
                dragLocked ? client.sendMouseDown() : client.sendMouseUp()
            }
        }
        .frame(height: 44)
        .padding(.trailing, 40)
        .accessibilityElement(children: .contain)
    }

    private func controlButton(_ title: String, systemImage: String, active: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
            .accessibilityLabel(title)
            .foregroundStyle(active ? Color.black : Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(active ? accent : control)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? accent : Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var scrollRail: some View {
        GeometryReader { geometry in
            let thumbHeight: CGFloat = 92
            let limit = max(0, (geometry.size.height - thumbHeight) / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.12, green: 0.13, blue: 0.14))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.14)))
                VStack(spacing: 3) {
                    Image(systemName: "chevron.up").font(.caption2.bold())
                    Image(systemName: "line.3.horizontal").font(.caption.bold())
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                    .foregroundStyle(Color.black.opacity(0.62))
                    .frame(width: 32, height: thumbHeight)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .offset(y: scrollOffset)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let next = max(-limit, min(limit, value.location.y - geometry.size.height / 2))
                    let delta = next - scrollOffset
                    scrollOffset = next
                    dismissKeyboard()
                    client.sendScroll(amount: -delta / 1.5)
                    if limit > 0, abs(next) >= limit - 1 {
                        startEdgeScroll(direction: next > 0 ? -1 : 1)
                    } else {
                        stopEdgeScroll()
                    }
                }
                .onEnded { _ in
                    stopEdgeScroll()
                    withAnimation(.spring(response: 0.25)) { scrollOffset = 0 }
                })
        }
        .frame(width: 42)
        .accessibilityElement()
        .accessibilityLabel("スクロール")
        .accessibilityHint("上下にドラッグしてWindows画面をスクロールします")
        .accessibilityAdjustableAction { direction in
            client.sendScroll(amount: direction == .increment ? 12 : -12)
        }
    }

    private var keyboardPanel: some View {
        VStack(spacing: 6) {
            TextField(
                "",
                text: $inputText,
                prompt: Text("iPhoneキーボードで入力").foregroundStyle(Color(white: 0.36)),
                axis: .vertical
            )
                .accessibilityLabel("Windowsへ送る文字")
                .accessibilityHint("iPhoneキーボードで入力します")
                .lineLimit(1).focused($inputFocused).textFieldStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.black).tint(.black).padding(.horizontal, 12)
                .frame(height: 44).background(Color(white: 0.97)).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 7) {
                keyboardButton("送信", systemImage: "paperplane.fill", primary: true) {
                    sendInput(pressEnter: false)
                }
                keyboardButton("エンター", systemImage: "return") {
                    sendInput(pressEnter: true)
                }
                keyboardButton("⌫", compact: true) {
                    if inputText.isEmpty { client.sendBackspace() } else { inputText.removeLast() }
                }
            }
            .frame(height: 42)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("送信") { sendInput(pressEnter: false) }
                    .disabled(inputText.isEmpty)
                Button("エンター") { sendInput(pressEnter: true) }
                    .disabled(inputText.isEmpty)
                Spacer()
                Button("完了") { dismissKeyboard() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func keyboardButton(_ title: String, systemImage: String? = nil,
                                primary: Bool = false, compact: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.bold())
        }
            .accessibilityLabel(title)
            .foregroundStyle(primary ? Color.black : Color.white)
            .frame(maxWidth: compact ? 58 : .infinity, maxHeight: .infinity)
            .background(primary ? accent : control)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sendInput(pressEnter: Bool) {
        guard !inputText.isEmpty else { return }
        client.sendText(inputText, pressEnter: pressEnter)
        inputText = ""
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        inputFocused = false
    }

    private func connectFromQRCode(_ value: String) {
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.hasPrefix("ws://") || address.hasPrefix("wss://") else { return }
        receiverAddress = address
        client.connect(to: address)
    }

    private func startEdgeScroll(direction: Double) {
        guard edgeScrollDirection != direction || edgeScrollTimer == nil else { return }
        stopEdgeScroll()
        edgeScrollDirection = direction
        client.sendScroll(amount: direction * 12)
        edgeScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            Task { @MainActor in
                client.sendScroll(amount: direction * 12)
            }
        }
    }

    private func stopEdgeScroll() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
        edgeScrollDirection = 0
    }

    private func gestureHint(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.055), in: Capsule())
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Windows受信機") {
                    TextField("192.168.1.2:8000", text: $receiverAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(client.state == .connected ? "切断" : "接続") {
                        client.state == .connected ? client.disconnect() : client.connect(to: receiverAddress)
                    }
                    Text(client.state.label).foregroundStyle(.secondary)
                    if !client.recoveryHint.isEmpty {
                        Text(client.recoveryHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if client.state != .connected {
                        Button("今すぐ再接続") { client.connect(to: receiverAddress) }
                    }
                    Button("QRコードを読み取って接続") {
                        showingSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showingQRScanner = true
                        }
                    }
                }
                if !discovery.receivers.isEmpty {
                    Section("自動検出") {
                        ForEach(discovery.receivers) { receiver in
                            Button(receiver.name) {
                                receiverAddress = receiver.address
                                client.connect(to: receiver.address)
                                showingSettings = false
                            }
                        }
                    }
                }
                Section("カーソル感度") {
                    Slider(value: $sensitivity, in: 0.5...3.0, step: 0.1)
                    Text(String(format: "%.1fx", sensitivity))
                }

                Section("ヘルプ") {
                    Button("操作と接続のチュートリアル") {
                        showingSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showingTutorial = true
                        }
                    }
                    NavigationLink("接続できないとき") {
                        ConnectionHelpView()
                    }
                }
            }
            .navigationTitle("SmartMouse設定")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { showingSettings = false } } }
        }
    }
}

private struct ConnectionHelpView: View {
    var body: some View {
        List {
            helpRow(
                "1", "受信機を確認",
                "WindowsでSmartMouseReceiver.exeを開き、QRコードが表示されたままにします。"
            )
            helpRow(
                "2", "同じWi‑Fiを確認",
                "iPhoneとPCを同じWi‑Fiへ接続します。ゲスト・ホテル・公共Wi‑Fiでは通信できない場合があります。"
            )
            helpRow(
                "3", "Windowsの許可を確認",
                "ファイアウォールの確認画面では「プライベート ネットワーク」を許可します。"
            )
            helpRow(
                "4", "VPNを一時的に切る",
                "iPhoneまたはPCでVPNを使っている場合は、一度オフにして接続を試します。"
            )
            helpRow(
                "5", "QRコードを読み直す",
                "PCのIPアドレスが変わることがあるため、現在表示されているQRコードを読み取ります。"
            )
        }
        .navigationTitle("接続できないとき")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline.bold())
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(Color(red: 0.20, green: 0.86, blue: 0.62), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ImmediateControlButton: View {
    let title: String
    let systemImage: String
    let active: Bool
    let accent: Color
    let control: Color
    let action: () -> Void
    @State private var fired = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(active ? Color.black : Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? accent : control)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? accent : Color.white.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !fired else { return }
                    fired = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                }
                .onEnded { _ in fired = false }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }
}
