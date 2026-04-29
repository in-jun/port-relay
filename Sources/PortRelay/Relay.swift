import Network
import Foundation

protocol Relay: AnyObject, Sendable {
    func start(config: RelayConfig, logger: @escaping @Sendable (String) -> Void)
    func stop()
}

final class RelaySession: @unchecked Sendable {
    let inbound: NWConnection
    let outbound: NWConnection
    private var cancelled = false

    init(inbound: NWConnection, outbound: NWConnection) {
        self.inbound = inbound
        self.outbound = outbound
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        inbound.cancel()
        outbound.cancel()
    }
}
