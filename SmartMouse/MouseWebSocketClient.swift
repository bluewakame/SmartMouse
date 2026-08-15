import Foundation
import Combine

@MainActor
final class MouseWebSocketClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "未接続"
            case .connecting: return "接続中…"
            case .connected: return "接続済み"
            case .failed: return "接続エラー"
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var recoveryHint = ""
    @Published private(set) var reconnectAttempt = 0
    @Published private(set) var latencyMilliseconds: Int?
    @Published private(set) var receiverVersion = ""
    @Published private(set) var receiverProtocol = ""
    @Published private(set) var protocolCompatible = true
    /// QRコードの読み取りが必要な状態。Receiver再起動でトークンが変わった場合も立つ。
    @Published private(set) var needsPairing = false

    static let requiredProtocol = "2"

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
    private var handshakeCompleted = false
    private var pendingMoveX = 0.0
    private var pendingMoveY = 0.0
    private var moveFlushTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var lastAddress: String?
    private var shouldReconnect = false

    func connect(to address: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        shouldReconnect = true
        needsPairing = false
        lastAddress = address
        reconnectAttempt = 0
        beginConnection(to: address)
    }

    /// 保存済みのアドレスだけで接続を再開できるか。トークンが無ければReceiverに拒否される。
    nonisolated static func canConnect(to address: String) -> Bool {
        guard let url = webSocketURL(from: address) else { return false }
        return pairingToken(from: url) != nil
    }

    func retryNow() {
        guard let lastAddress else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        beginConnection(to: lastAddress)
    }

    private func beginConnection(to address: String) {
        cancelTransport()
        handshakeCompleted = false

        guard let url = Self.webSocketURL(from: address) else {
            state = .failed("接続先の形式が正しくありません")
            recoveryHint = "QRコードをもう一度読み取るか、設定のアドレスを確認してください。"
            needsPairing = true
            return
        }

        // Receiverは起動ごとに変わる合言葉付きのURLしか受け付けない。
        // 合言葉が無いまま接続してもすぐ切断されるので、先にQRコードへ誘導する。
        guard Self.pairingToken(from: url) != nil else {
            state = .failed("QRコードの読み取りが必要です")
            recoveryHint = "Windowsの画面に出ているQRコードを読み取ると、接続先と合言葉がまとめて設定されます。"
            needsPairing = true
            return
        }

        state = .connecting
        recoveryHint = reconnectAttempt > 0 ? "自動で再接続しています（\(reconnectAttempt)回目）" : ""
        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        receiveHandshake(from: newTask)
    }

    func disconnect() {
        shouldReconnect = false
        lastAddress = nil
        reconnectAttempt = 0
        recoveryHint = ""
        latencyMilliseconds = nil
        receiverVersion = ""
        receiverProtocol = ""
        protocolCompatible = true
        needsPairing = false
        reconnectTask?.cancel()
        reconnectTask = nil
        cancelTransport()
        state = .disconnected
    }

    private func cancelTransport() {
        moveFlushTask?.cancel()
        moveFlushTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pendingMoveX = 0
        pendingMoveY = 0
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func sendMove(dx: Double, dy: Double) {
        pendingMoveX += dx
        pendingMoveY += dy
        guard moveFlushTask == nil else { return }
        moveFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            self?.flushPendingMove()
        }
    }

    func sendClick() {
        send(payload: ["type": "click", "button": "left"])
    }

    func sendRightClick() {
        send(payload: ["type": "click", "button": "right"])
    }

    func sendDoubleClick() {
        send(payload: ["type": "double_click"])
    }

    func sendMouseDown() {
        flushPendingMove()
        send(payload: ["type": "mouse_down", "button": "left"])
    }

    func sendMouseUp() {
        flushPendingMove()
        send(payload: ["type": "mouse_up", "button": "left"])
    }

    func sendShortcut(_ shortcut: String) {
        send(payload: ["type": "shortcut", "shortcut": shortcut])
    }

    func sendText(_ text: String, pressEnter: Bool = false) {
        guard !text.isEmpty else { return }
        send(payload: [
            "type": pressEnter ? "paste_enter_text" : "paste_text",
            "text": text
        ])
    }

    func sendBackspace() {
        send(payload: ["type": "key", "key": "backspace"])
    }

    func sendEnter() {
        send(payload: ["type": "key", "key": "enter"])
    }

    func sendReleaseAll() {
        flushPendingMove()
        send(payload: ["type": "release_all"])
    }

    func sendScroll(amount: Double) {
        send(payload: [
            "type": "scroll",
            "amount": max(-30, min(30, amount))
        ])
    }

    private func flushPendingMove() {
        moveFlushTask?.cancel()
        moveFlushTask = nil
        let dx = pendingMoveX.rounded()
        let dy = pendingMoveY.rounded()
        pendingMoveX -= dx
        pendingMoveY -= dy
        guard dx != 0 || dy != 0 else { return }
        send(payload: [
            "type": "move",
            "dx": max(-100, min(100, dx)),
            "dy": max(-100, min(100, dy))
        ])
    }

    private func send(payload: [String: Any]) {
        guard state == .connected, let task else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { [weak self, weak task] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, let task, self.task === task else { return }
                self.handleConnectionFailure(error, task: task)
            }
        }
    }

    private func receiveNextMessage(from task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            Task { @MainActor in
                guard let self, let task, self.task === task else { return }
                switch result {
                case .success:
                    self.receiveNextMessage(from: task)
                case .failure(let error):
                    self.handleConnectionFailure(error, task: task)
                }
            }
        }
    }

    private func receiveHandshake(from task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            Task { @MainActor in
                guard let self, let task, self.task === task else { return }
                switch result {
                case .success(let message):
                    guard case .string(let text) = message,
                          let data = text.data(using: .utf8),
                          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          payload["type"] as? String == "receiver_ready" else {
                        self.state = .failed("Receiverを確認できません")
                        self.recoveryHint = "\(Self.displayEndpoint(for: self.lastAddress))はSmartMouse Receiverとして応答しませんでした。最新版のReceiverが起動しているか確認してください。"
                        task.cancel(with: .policyViolation, reason: nil)
                        self.task = nil
                        return
                    }
                    self.receiverVersion = payload["version"] as? String ?? ""
                    self.receiverProtocol = payload["protocol"] as? String ?? "不明"
                    self.protocolCompatible = self.receiverProtocol == Self.requiredProtocol
                    guard self.protocolCompatible else {
                        self.state = .failed("Receiverの更新が必要です")
                        // 配布パッケージ名とコード側のバージョンは独立しているため、
                        // 実際に受け取った値と接続先を出さないと切り分けができない。
                        self.recoveryHint = """
                        接続先 \(Self.displayEndpoint(for: self.lastAddress)) のReceiver \
                        v\(self.receiverVersion.isEmpty ? "不明" : self.receiverVersion) は \
                        プロトコル \(self.receiverProtocol) を返しました。\
                        このアプリはプロトコル \(Self.requiredProtocol) が必要です。
                        """
                        task.cancel(with: .policyViolation, reason: nil)
                        self.task = nil
                        return
                    }
                    self.handshakeCompleted = true
                    self.needsPairing = false
                    self.state = .connected
                    self.recoveryHint = ""
                    self.reconnectAttempt = 0
                    self.receiveNextMessage(from: task)
                    self.startHeartbeat(for: task)
                case .failure(let error):
                    self.handleConnectionFailure(error, task: task)
                }
            }
        }
    }

    private func startHeartbeat(for task: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, let task, self.task === task else { return }
                let startedAt = Date()
                task.sendPing { [weak self, weak task] error in
                    Task { @MainActor in
                        guard let self, let task, self.task === task else { return }
                        if let error {
                            self.handleConnectionFailure(error, task: task)
                        } else {
                            self.latencyMilliseconds = max(1, Int(Date().timeIntervalSince(startedAt) * 1_000))
                        }
                    }
                }
            }
        }
    }

    private func handleConnectionFailure(_ error: Error, task failedTask: URLSessionWebSocketTask) {
        guard task === failedTask else { return }
        let closeCode = failedTask.closeCode
        let failedBeforeHandshake = !handshakeCompleted
        task = nil
        latencyMilliseconds = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil

        // Receiverは合言葉が違うとWebSocketを開いた直後にpolicy violationで閉じる。
        // 同じ合言葉で再試行しても通らないため、再接続せずQRコードへ誘導する。
        if closeCode == .policyViolation || (failedBeforeHandshake && Self.isServerSideClose(error)) {
            needsPairing = true
            state = .failed("接続の許可が切れています")
            recoveryHint = "Receiverを起動し直すとQRコードが変わります。Windows画面の新しいQRコードを読み取ってください。"
            return
        }

        let details = Self.friendlyMessage(for: error)
        state = .failed(details.title)
        recoveryHint = details.hint
        scheduleReconnect()
    }

    /// PCまで届いた後に切られたか（＝合言葉切れの可能性が高いか）を判定する。
    nonisolated private static func isServerSideClose(_ error: Error) -> Bool {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return false
        default:
            return true
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect, let lastAddress, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = min(15.0, pow(2.0, Double(min(reconnectAttempt - 1, 4))))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.beginConnection(to: lastAddress)
        }
    }

    private static func friendlyMessage(for error: Error) -> (title: String, hint: String) {
        let code = (error as? URLError)?.code
        switch code {
        case .notConnectedToInternet:
            return ("Wi‑Fiに接続されていません", "iPhoneとWindows PCを同じWi‑Fiにつないでください。")
        case .timedOut, .cannotConnectToHost, .cannotFindHost:
            return ("Windows受信機が見つかりません", "PCでSmartMouseReceiver.exeが起動中か、QRコードが最新か確認してください。")
        case .networkConnectionLost:
            return ("PCとの接続が切れました", "同じWi‑Fi内なら自動的に再接続します。")
        default:
            return ("Windows PCへ接続できません", "受信機、同じWi‑Fi、Windowsファイアウォール、VPNの順に確認してください。")
        }
    }

    /// 画面表示用のホスト名とポート。ペアリングトークンは意図的に含めない。
    private static func displayEndpoint(for address: String?) -> String {
        guard let address, let url = webSocketURL(from: address), let host = url.host else {
            return "接続先不明"
        }
        return "\(host):\(url.port ?? 8000)"
    }

    nonisolated static func webSocketURL(from address: String) -> URL? {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "ws://\(value)"
        }
        guard var components = URLComponents(string: value), components.host != nil else {
            return nil
        }
        // Receiver画面のWeb UI用URL（http://…?token=…）を読み取っても接続できるようにする。
        switch components.scheme?.lowercased() {
        case "ws", "wss":
            break
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            return nil
        }
        if components.port == nil { components.port = 8000 }
        if components.path.isEmpty || components.path == "/" { components.path = "/ws" }
        return components.url
    }

    nonisolated private static func pairingToken(from url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == "token" })?.value,
              token.count == 32 else { return nil }
        return token
    }
}
