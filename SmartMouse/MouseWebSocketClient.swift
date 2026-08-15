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
            case .failed(let message): return "エラー: \(message)"
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)

    func connect(to address: String) {
        disconnect()

        guard let url = Self.webSocketURL(from: address) else {
            state = .failed("アドレスを確認してください")
            return
        }

        state = .connecting
        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()

        newTask.sendPing { [weak self, weak newTask] error in
            Task { @MainActor in
                guard let self, let newTask, self.task === newTask else { return }
                if let error {
                    self.state = .failed(error.localizedDescription)
                    self.task = nil
                } else {
                    self.state = .connected
                    self.receiveNextMessage(from: newTask)
                }
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
    }

    func sendMove(dx: Double, dy: Double) {
        send(payload: [
            "type": "move",
            "dx": max(-100, min(100, dx)),
            "dy": max(-100, min(100, dy))
        ])
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
        send(payload: ["type": "mouse_down", "button": "left"])
    }

    func sendMouseUp() {
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

    private func send(payload: [String: Any]) {
        guard state == .connected, let task else { return }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { [weak self, weak task] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, let task, self.task === task else { return }
                self.state = .failed(error.localizedDescription)
                self.task = nil
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
                    self.state = .failed(error.localizedDescription)
                    self.task = nil
                }
            }
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
