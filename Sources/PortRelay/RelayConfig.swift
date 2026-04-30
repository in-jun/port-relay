import Foundation
import Network

enum RelayProtocol: String, CaseIterable, Sendable {
    case udp = "UDP"
    case tcp = "TCP"
    case both = "Both"
}

struct RelayConfig: Sendable {
    let listenPort: NWEndpoint.Port
    let remoteHost: NWEndpoint.Host
    let remotePort: NWEndpoint.Port
    let proto: RelayProtocol

    var remoteEndpoint: String { "\(remoteHost):\(remotePort)" }
}

extension RelayConfig {
    enum ValidationError: LocalizedError {
        case invalidListenPort
        case invalidRemotePort
        case emptyHost

        var errorDescription: String? {
            switch self {
            case .invalidListenPort: "Listen port must be 1–65535"
            case .invalidRemotePort: "Remote port must be 1–65535"
            case .emptyHost: "Remote host is required"
            }
        }
    }

    init(listenPort: String, remoteHost: String, remotePort: String, proto: RelayProtocol) throws {
        guard let lp = UInt16(listenPort).flatMap(NWEndpoint.Port.init(rawValue:)) else {
            throw ValidationError.invalidListenPort
        }
        let host = remoteHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw ValidationError.emptyHost }
        guard let rp = UInt16(remotePort).flatMap(NWEndpoint.Port.init(rawValue:)) else {
            throw ValidationError.invalidRemotePort
        }
        self.listenPort = lp
        self.remoteHost = NWEndpoint.Host(host)
        self.remotePort = rp
        self.proto = proto
    }
}
