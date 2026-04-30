import Foundation
import Network
import os

struct RelayBehavior: Sendable {
    let label: String
    let parameters: @Sendable () -> NWParameters
    let receive: @Sendable (NWConnection, @escaping @Sendable (Data?, Bool, Error?) -> Void) -> Void
    let send: @Sendable (NWConnection, Data, @escaping @Sendable (Error?) -> Void) -> Void

    static let tcp = RelayBehavior(
        label: "TCP",
        parameters: {
            let opts = NWProtocolTCP.Options()
            opts.noDelay = true
            return NWParameters(tls: nil, tcp: opts)
        },
        receive: { conn, cb in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                cb(data, complete, error)
            }
        },
        send: { conn, data, cb in
            conn.send(content: data, completion: .contentProcessed { cb($0) })
        }
    )

    static let udp = RelayBehavior(
        label: "UDP",
        parameters: { .udp },
        receive: { conn, cb in
            conn.receiveMessage { data, _, complete, error in
                cb(data, complete, error)
            }
        },
        send: { conn, data, cb in
            conn.send(content: data, completion: .idempotent)
            cb(nil)
        }
    )
}

extension RelayProtocol {
    var behaviors: [RelayBehavior] {
        switch self {
        case .udp: [.udp]
        case .tcp: [.tcp]
        case .both: [.udp, .tcp]
        }
    }
}

final class PortRelay: Sendable {
    private final class Session: Hashable, @unchecked Sendable {
        let inbound: NWConnection
        let outbound: NWConnection
        init(_ inbound: NWConnection, _ outbound: NWConnection) {
            self.inbound = inbound
            self.outbound = outbound
        }
        func cancel() {
            inbound.cancel()
            outbound.cancel()
        }
        static func == (lhs: Session, rhs: Session) -> Bool { lhs === rhs }
        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    private struct State {
        var listener: NWListener?
        var sessions: Set<Session> = []
    }

    private let behavior: RelayBehavior
    private let config: RelayConfig
    private let log: @Sendable (String) -> Void
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(behavior: RelayBehavior, config: RelayConfig, log: @escaping @Sendable (String) -> Void) {
        self.behavior = behavior
        self.config = config
        self.log = log
        self.queue = DispatchQueue(label: "relay.\(behavior.label.lowercased())", qos: .userInteractive)
    }

    func start() throws {
        let listener = try NWListener(using: behavior.parameters(), on: config.listenPort)
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .failed(let error) = state else { return }
            self.log("\(self.behavior.label): listener failed (\(error.localizedDescription))")
        }
        listener.start(queue: queue)
        state.withLock { $0.listener = listener }
        log("\(behavior.label): listening on \(config.listenPort)")
    }

    func stop() {
        let snapshot = state.withLock { state -> State in
            let copy = state
            state.listener = nil
            state.sessions.removeAll()
            return copy
        }
        snapshot.listener?.cancel()
        snapshot.sessions.forEach { $0.cancel() }
    }

    private func accept(_ inbound: NWConnection) {
        let connQueue = DispatchQueue(label: "relay.\(behavior.label.lowercased()).conn", qos: .userInteractive)
        inbound.start(queue: connQueue)

        let outbound = NWConnection(host: config.remoteHost, port: config.remotePort, using: behavior.parameters())
        outbound.start(queue: connQueue)

        let session = Session(inbound, outbound)
        state.withLock { $0.sessions.insert(session) }
        log("\(behavior.label): new session → \(config.remoteEndpoint)")

        let cleanup: @Sendable () -> Void = { [weak self] in
            session.cancel()
            self?.state.withLock { _ = $0.sessions.remove(session) }
        }

        for connection in [inbound, outbound] {
            connection.stateUpdateHandler = { state in
                if case .failed = state { cleanup() }
            }
        }

        pump(from: inbound, to: outbound, cleanup: cleanup)
        pump(from: outbound, to: inbound, cleanup: cleanup)
    }

    private func pump(from: NWConnection, to: NWConnection, cleanup: @escaping @Sendable () -> Void) {
        let behavior = self.behavior
        @Sendable func loop() {
            behavior.receive(from) { data, complete, error in
                if let data, !data.isEmpty {
                    behavior.send(to, data) { sendError in
                        if sendError != nil { cleanup(); return }
                        loop()
                    }
                    return
                }
                if complete || error != nil { cleanup() }
            }
        }
        loop()
    }
}
