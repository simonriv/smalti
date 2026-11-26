/// What the port view asks for.
public struct PortQuery: Equatable, Sendable {
    public let filter: String
    public let order: PortOrder

    public init(filter: String, order: PortOrder) {
        self.filter = filter
        self.order = order
    }
}

/// One listener: a process on a port and transport, with every address it listens on.
public struct PortRow: Equatable, Sendable {
    public let pid: Int32
    public let transport: Transport
    public let port: UInt16
    public let addresses: [String]
    public let scope: ListenScope
    /// Nil when the process ended between reading the sockets and the processes.
    public let process: ProcessRow?
}

public struct PortSummary: Equatable, Sendable {
    public let total: Int
    public let openToNetwork: Int
}

/// The port view: listeners grouped by process, transport and port (IPv4 and IPv6 are one row).
public enum PortTable {
    public static func rows(
        sockets: [ListeningSocket], processes: [Int32: ProcessRow], paneNames: [PaneID: String], query: PortQuery
    ) -> [PortRow] {
        let filter = TextFilter(query.filter)
        return grouped(sockets, processes: processes)
            .filter { filter.isEmpty || filter.matches(fields(of: $0, paneNames)) }
            .sorted(by: comparator(query.order, paneNames))
    }

    public static func summary(_ rows: [PortRow]) -> PortSummary {
        PortSummary(total: rows.count, openToNetwork: rows.filter(\.scope.isOpenToNetwork).count)
    }

    private struct Key: Hashable {
        let pid: Int32
        let transport: Transport
        let port: UInt16
    }

    private static func grouped(_ sockets: [ListeningSocket], processes: [Int32: ProcessRow]) -> [PortRow] {
        var addresses: [Key: [String]] = [:]
        var order: [Key] = []
        for socket in sockets {
            let key = Key(pid: socket.pid, transport: socket.transport, port: socket.port)
            if addresses[key] == nil { order.append(key) }
            if addresses[key]?.contains(socket.address) != true { addresses[key, default: []].append(socket.address) }
        }
        return order.map { key in
            let list = addresses[key] ?? []
            return PortRow(
                pid: key.pid, transport: key.transport, port: key.port, addresses: list, scope: .of(list),
                process: processes[key.pid])
        }
    }

    private static func fields(of row: PortRow, _ paneNames: [PaneID: String]) -> [String] {
        let process = row.process.map { ProcessTable.fields(of: $0, paneNames) } ?? [String(row.pid)]
        return [String(row.port), row.transport.rawValue] + row.addresses + process
    }

    private static func comparator(
        _ order: PortOrder, _ paneNames: [PaneID: String]
    ) -> (PortRow, PortRow) -> Bool {
        let byPort: (PortRow, PortRow) -> Bool = { ($0.port, $0.transport, $0.pid) < ($1.port, $1.transport, $1.pid) }
        switch order {
        case .port: return byPort
        case .process: return ordered(by: { $0.process.map { ProcessTable.folded($0.name) } }, then: byPort)
        case .pane:
            return ordered(by: { $0.process?.pane.flatMap { paneNames[$0] }.map(ProcessTable.folded) }, then: byPort)
        }
    }

    /// Sorts by `key` with the rows without one last, then by `then`.
    private static func ordered(
        by key: @escaping (PortRow) -> String?, then: @escaping (PortRow, PortRow) -> Bool
    ) -> (PortRow, PortRow) -> Bool {
        { lhs, rhs in
            switch (key(lhs), key(rhs)) {
            case let (left?, right?) where left != right: left < right
            case (.some, nil): true
            case (nil, .some): false
            default: then(lhs, rhs)
            }
        }
    }
}
