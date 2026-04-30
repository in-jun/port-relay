import Foundation
import Observation

@MainActor
@Observable
final class RelayEngine {
    enum StartError: LocalizedError {
        case allFailed

        var errorDescription: String? {
            switch self {
            case .allFailed: "Failed to bind. Check if the listen port is already in use."
            }
        }
    }

    private(set) var isRunning = false
    private(set) var logs: [LogEntry] = []

    private var relays: [PortRelay] = []
    private let keeper = BackgroundKeeper()

    func start(config: RelayConfig) throws {
        stop()

        let logger: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.append(message) }
        }

        relays = config.proto.behaviors.compactMap { behavior in
            let relay = PortRelay(behavior: behavior, config: config, log: logger)
            do {
                try relay.start()
                return relay
            } catch {
                append("\(behavior.label): bind failed (\(error.localizedDescription))")
                return nil
            }
        }

        guard !relays.isEmpty else {
            throw StartError.allFailed
        }

        keeper.start()
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
