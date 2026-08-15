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

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
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
        lastAddress = address
        reconnectAttempt = 0
        beginConnection(to: address)
    }

    func retryNow() {
        guard let lastAddress else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        beginConnection(to: lastAddress)
    }

    private func beginConnection(to address: String) {
        cancelTransport()

        guard let url = Self.webSocketURL(from: address) else {
            state = .failed("接続先の形式が正しくありません")
            recoveryHint = "QRコードをもう一度読み取るか、設定のアドレスを確認してください。"
            return
        }

        state = .connecting
        recoveryHint = reconnectAttempt > 0 ? "自動で再接続しています（\(reconnectAttempt)回目）" : ""
        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()

        newTask.sendPing { [weak self, weak newTask] error in
            Task { @MainActor in
                guard let self, let newTask, self.task === newTask else { return }
                if let error {
                    self.handleConnectionFailure(error, task: newTask)
                } else {
                    self.state = .connected
                    self.recoveryHint = ""
                    self.reconnectAttempt = 0
                    self.receiveNextMessage(from: newTask)
                    self.startHeartbeat(for: newTask)
                }
            }
        }
    }

    func disconnect() {
        shouldReconnect = false
        lastAddress = nil
        reconnectAttempt = 0
        recoveryHint = ""
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

    private func startHeartbeat(for task: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, let task, self.task === task else { return }
                task.sendPing { [weak self, weak task] error in
                    guard let error else { return }
                    Task { @MainActor in
                        guard let self, let task, self.task === task else { return }
                        self.handleConnectionFailure(error, task: task)
                    }
                }
            }
        }
    }

    private func handleConnectionFailure(_ error: Error, task failedTask: URLSessionWebSocketTask) {
        guard task === failedTask else { return }
        task = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil

        let details = Self.friendlyMessage(for: error)
        state = .failed(details.title)
        recoveryHint = details.hint
        scheduleReconnect()
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

    private static func webSocketURL(from address: String) -> URL? {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.hasPrefix("ws://") && !value.hasPrefix("wss://") {
            value = "ws://\(value)"
        }
        guard var components = URLComponents(string: value), components.host != nil else {
            return nil
        }
        if components.port == nil { components.port = 8000 }
        if components.path.isEmpty || components.path == "/" { components.path = "/ws" }
        return components.url
    }
}
