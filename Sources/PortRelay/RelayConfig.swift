import Foundation

enum RelayProtocol: String, CaseIterable, Sendable {
    case udp = "UDP"
    case tcp = "TCP"
    case both = "Both"
}

struct RelayConfig: Sendable {
    let listenPort: UInt16
    let remoteHost: String
    let remotePort: UInt16
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

    static func validate(
        listenPort: String,
        remoteHost: String,
        remotePort: String
    ) -> Result<(UInt16, String, UInt16), ValidationError> {
        guard let lp = UInt16(listenPort), lp > 0 else {
            return .failure(.invalidListenPort)
        }
        guard !remoteHost.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(.emptyHost)
        }
        guard let rp = UInt16(remotePort), rp > 0 else {
            return .failure(.invalidRemotePort)
        }
        return .success((lp, remoteHost.trimmingCharacters(in: .whitespaces), rp))
    }
}
