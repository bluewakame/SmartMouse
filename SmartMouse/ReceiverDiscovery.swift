import Combine
import Foundation
import Network

@MainActor
final class ReceiverDiscovery: ObservableObject {
    struct Receiver: Identifiable, Equatable {
        let name: String
        let address: String
        var id: String { address }
    }

    @Published private(set) var receivers: [Receiver] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_smartmouse._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let receivers = results.compactMap(Self.receiver(from:)).sorted { $0.name < $1.name }
            Task { @MainActor in self?.receivers = receivers }
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        receivers = []
    }

    private nonisolated static func receiver(from result: NWBrowser.Result) -> Receiver? {
        guard case let .service(name, _, _, _) = result.endpoint,
              name.hasPrefix("SmartMouse-") else { return nil }
        let encodedIP = name.dropFirst("SmartMouse-".count)
        let address = encodedIP.replacingOccurrences(of: "-", with: ".") + ":8000"
        return Receiver(name: "SmartMouse (\(address))", address: address)
    }
}
