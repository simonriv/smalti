/// The transport a socket speaks.
public enum Transport: String, Equatable, Hashable, Sendable, Comparable {
    case tcp = "TCP"
    case udp = "UDP"

    public static func < (lhs: Transport, rhs: Transport) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A TCP socket in LISTEN or an unconnected UDP socket with a local port: what lsof shows as listening.
public struct ListeningSocket: Equatable, Hashable, Sendable {
    public let pid: Int32
    public let transport: Transport
    public let port: UInt16
    /// The local address as lsof writes it without brackets: `127.0.0.1`, `::1`, `0.0.0.0`, `::`.
    public let address: String

    public init(pid: Int32, transport: Transport, port: UInt16, address: String) {
        self.pid = pid
        self.transport = transport
        self.port = port
        self.address = address
    }
}

/// Who can reach a port: this Mac only, every interface, or the given addresses.
public enum ListenScope: Equatable, Sendable {
    case local
    case all
    case specific([String])

    public var isOpenToNetwork: Bool { self != .local }

    /// The scope of one listener's addresses (IPv4 and IPv6 usually come in pairs).
    public static func of(_ addresses: [String]) -> ListenScope {
        if addresses.contains(where: isWildcard) { return .all }
        let concrete = addresses.filter { !isLoopback($0) }
        return concrete.isEmpty ? .local : .specific(concrete)
    }

    static func isWildcard(_ address: String) -> Bool {
        ["0.0.0.0", "::", "*"].contains(address)
    }

    static func isLoopback(_ address: String) -> Bool {
        address.hasPrefix("127.") || address == "::1" || address.hasPrefix("::ffff:127.")
    }
}
