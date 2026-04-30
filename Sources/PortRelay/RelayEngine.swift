import Foundation
import Observation

@MainActor
@Observable
final class RelayEngine {
    private(set) var isRunning = false
    private(set) var logs: [LogEntry] = []

    private var relays: [PortRelay] = []
    private let keeper = BackgroundKeeper()

    func start(config: RelayConfig) {
        stop()
        keeper.start()

        let logger: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.append(message) }
        }

        relays = config.proto.behaviors.map { behavior in
            let relay = PortRelay(behavior: behavior, config: config, log: logger)
            relay.start()
            return relay
        }

        isRunning = true
    }

    func stop() {
        relays.forEach { $0.stop() }
        relays.removeAll()
        keeper.stop()
        if isRunning { append("Stopped") }
        isRunning = false
    }

    private func append(_ message: String) {
        logs.append(LogEntry(timestamp: Date(), message: message))
        if logs.count > 200 { logs.removeFirst() }
    }
}
