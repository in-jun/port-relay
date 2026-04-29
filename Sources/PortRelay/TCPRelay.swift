import Network
import Foundation

final class TCPRelay: Relay, @unchecked Sendable {
    private var listener: NWListener?
    private var sessions: [RelaySession] = []
    private let queue = DispatchQueue(label: "tcp-relay", qos: .userInitiated)
    private var log: (@Sendable (String) -> Void)?

    func start(config: RelayConfig, logger: @escaping @Sendable (String) -> Void) {
        self.log = logger
        guard let port = NWEndpoint.Port(rawValue: config.listenPort) else { return }
        guard let newListener = try? NWListener(using: .tcp, on: port) else {
            logger("TCP: failed to bind \(config.listenPort)")
            return
        }

        newListener.newConnectionHandler = { [weak self] inbound in
            self?.handleConnection(inbound, config: config)
        }

        newListener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.log?("TCP listener failed: \(error)")
            }
        }

        newListener.start(queue: queue)
        listener = newListener
        logger("TCP: listening on \(config.listenPort)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        sessions.forEach { $0.cancel() }
        sessions.removeAll()
    }

    private func handleConnection(_ inbound: NWConnection, config: RelayConfig) {
        inbound.start(queue: queue)

        let outbound = NWConnection(
            host: NWEndpoint.Host(config.remoteHost),
            port: NWEndpoint.Port(rawValue: config.remotePort)!,
            using: .tcp
        )
        outbound.start(queue: queue)

        let session = RelaySession(inbound: inbound, outbound: outbound)
        sessions.append(session)
        log?("TCP: new session → \(config.remoteEndpoint)")

        let cleanup: @Sendable () -> Void = { [weak self] in
            session.cancel()
            self?.queue.async {
                self?.sessions.removeAll { $0 === session }
            }
        }

        inbound.stateUpdateHandler = { state in
            if case .failed = state { cleanup() }
        }
        outbound.stateUpdateHandler = { state in
            if case .failed = state { cleanup() }
        }

        func pipe(_ from: NWConnection, _ to: NWConnection) {
            from.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    to.send(content: data, completion: .contentProcessed { sendError in
                        if sendError != nil { cleanup(); return }
                        pipe(from, to)
                    })
                    return
                }
                if isComplete || error != nil { cleanup() }
            }
        }

        pipe(inbound, outbound)
        pipe(outbound, inbound)
    }
}
