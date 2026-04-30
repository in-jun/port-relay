import Network
import Foundation

final class UDPRelay: Relay, @unchecked Sendable {
    private var listener: NWListener?
    private var sessions: [RelaySession] = []
    private let queue = DispatchQueue(label: "udp-relay", qos: .userInteractive)
    private var log: (@Sendable (String) -> Void)?

    func start(config: RelayConfig, logger: @escaping @Sendable (String) -> Void) {
        self.log = logger
        guard let port = NWEndpoint.Port(rawValue: config.listenPort) else { return }
        guard let newListener = try? NWListener(using: .udp, on: port) else {
            logger("UDP: failed to bind \(config.listenPort)")
            return
        }

        newListener.newConnectionHandler = { [weak self] inbound in
            self?.handleConnection(inbound, config: config)
        }

        newListener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.log?("UDP listener failed: \(error)")
            }
        }

        newListener.start(queue: queue)
        listener = newListener
        logger("UDP: listening on \(config.listenPort)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        sessions.forEach { $0.cancel() }
        sessions.removeAll()
    }

    private func handleConnection(_ inbound: NWConnection, config: RelayConfig) {
        let connQueue = DispatchQueue(label: "udp-conn", qos: .userInteractive)
        inbound.start(queue: connQueue)

        let outbound = NWConnection(
            host: NWEndpoint.Host(config.remoteHost),
            port: NWEndpoint.Port(rawValue: config.remotePort)!,
            using: .udp
        )
        outbound.start(queue: connQueue)

        let session = RelaySession(inbound: inbound, outbound: outbound)
        sessions.append(session)
        log?("UDP: new session → \(config.remoteEndpoint)")

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

        func relayClientToServer() {
            inbound.receiveMessage { [weak self] data, _, _, error in
                if error != nil { cleanup(); return }
                if let data { outbound.send(content: data, completion: .idempotent) }
                if self != nil { relayClientToServer() }
            }
        }

        func relayServerToClient() {
            outbound.receiveMessage { [weak self] data, _, _, error in
                if error != nil { cleanup(); return }
                if let data { inbound.send(content: data, completion: .idempotent) }
                if self != nil { relayServerToClient() }
            }
        }

        relayClientToServer()
        relayServerToClient()
    }
}
