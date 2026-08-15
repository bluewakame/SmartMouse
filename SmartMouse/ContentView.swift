import SwiftUI

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
                    keyboardPanel
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { settingsSheet }
        .sheet(isPresented: $showingTutorial) {
            TutorialView(onConnect: connectFromQRCode) {
                tutorialVersion = 2
                showingTutorial = false
            }
        }
        .fullScreenCover(isPresented: $showingQRScanner) {
            QRScannerView { result in
                showingQRScanner = false
                connectFromQRCode(result)
            } onCancel: {
                showingQRScanner = false
            }
            .ignoresSafeArea()
        }
        .onAppear {
            discovery.start()
            if tutorialVersion < 2 { showingTutorial = true }
        }
        .onDisappear {
            discovery.stop()
            stopEdgeScroll()
            if dragLocked { client.sendMouseUp() }
            client.disconnect()
        }
        .onReceive(discovery.$receivers) { receivers in
            guard client.state == .disconnected, let receiver = receivers.first else { return }
            receiverAddress = receiver.address
            client.connect(to: receiver.address)
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
                .padding(.top, 22)
                .padding(.horizontal, 16)
                .padding(.trailing, 58)
                .allowsHitTesting(false)
                Spacer()
                actionButtons
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(dragLocked ? 0.22 : 0.09), lineWidth: 1.5)
                .padding(.horizontal, 10)
                .padding(.top, 82)
                .padding(.bottom, 98)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            .fixedSize()
        }
        .padding(.top, 6)
        .padding(.trailing, 40)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            controlButton("コピー", systemImage: "doc.on.doc") {
                if dragLocked {
                    dragLocked = false
                    client.sendMouseUp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { client.sendShortcut("copy") }
                } else { client.sendShortcut("copy") }
            }
            controlButton("貼り付け", systemImage: "doc.on.clipboard") { client.sendShortcut("paste") }
            controlButton(dragLocked ? "離す" : "つかむ",
                          systemImage: dragLocked ? "hand.raised.slash.fill" : "hand.raised.fill",
                          active: dragLocked) {
                dragLocked.toggle()
                dragLocked ? client.sendMouseDown() : client.sendMouseUp()
            }
        }
        .frame(height: 52)
        .padding(.trailing, 40)
    }

    private func controlButton(_ title: String, systemImage: String, active: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
            .foregroundStyle(active ? Color.black : Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(active ? accent : control)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? accent : Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
    }

    private var keyboardPanel: some View {
        VStack(spacing: 9) {
            TextField(
                "",
                text: $inputText,
                prompt: Text("iPhoneキーボードで入力").foregroundStyle(Color(white: 0.36)),
                axis: .vertical
            )
                .lineLimit(1).focused($inputFocused).textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.black).tint(.black).padding(.horizontal, 14)
                .frame(height: 52).background(Color(white: 0.97)).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 9) {
                keyboardButton("送信", systemImage: "paperplane.fill", primary: true) {
                    sendInput(pressEnter: false)
                }
                keyboardButton("検索", systemImage: "magnifyingglass") {
                    sendInput(pressEnter: true)
                }
                keyboardButton("⌫", compact: true) {
                    if inputText.isEmpty { client.sendBackspace() } else { inputText.removeLast() }
                }
            }
            .frame(height: 50)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(Color(red: 0.055, green: 0.06, blue: 0.065))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("送信") { sendInput(pressEnter: false) }
                    .disabled(inputText.isEmpty)
                Button("検索") { sendInput(pressEnter: true) }
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
            HStack(spacing: 7) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline.bold())
        }
            .foregroundStyle(primary ? Color.black : Color.white)
            .frame(maxWidth: compact ? 70 : .infinity, maxHeight: .infinity)
            .background(primary ? accent : control)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                }
            }
            .navigationTitle("SmartMouse設定")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { showingSettings = false } } }
        }
    }
}
