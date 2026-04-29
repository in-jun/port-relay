import Foundation
import Observation

@MainActor
@Observable
final class RelayEngine {
    private(set) var isRunning = false
    private(set) var logs: [String] = []

    private var relays: [any Relay] = []

    func start(config: RelayConfig) {
        stop()

        let logger: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.appendLog(msg) }
        }

        switch config.proto {
        case .udp:
            let relay = UDPRelay()
            relay.start(config: config, logger: logger)
            relays.append(relay)
        case .tcp:
            let relay = TCPRelay()
            relay.start(config: config, logger: logger)
            relays.append(relay)
        case .both:
            let udp = UDPRelay()
            let tcp = TCPRelay()
            udp.start(config: config, logger: logger)
            tcp.start(config: config, logger: logger)
            relays.append(udp)
            relays.append(tcp)
        }

        isRunning = true
    }

    func stop() {
        relays.forEach { $0.stop() }
        relays.removeAll()
        if isRunning { appendLog("Stopped") }
        isRunning = false
    }

    private func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(msg)")
        if logs.count > 200 { logs.removeFirst() }
    }
}
