/// Why a process is not offered to stop or to lower its priority.
public enum ProtectionReason: Equatable, Sendable, CaseIterable {
    case otherUser
    case system
    case smalti
    case paneShell
    case zombie
}

public enum StopVerdict: Equatable, Sendable {
    case allowed
    case protected(ProtectionReason)

    public var isAllowed: Bool { self == .allowed }
}

/// What Smalti may stop or lower: only the person's own processes, never the system's, Smalti itself (any
/// instance), a pane's shell (⌘W closes it, warning first) or a zombie (spec F8, "Nunca se ofrecen").
public struct StopPolicy: Sendable {
    private let ownPID: Int32

    public init(ownPID: Int32) {
        self.ownPID = ownPID
    }

    public func verdict(for record: ProcessRecord, attribution: PaneAttribution) -> StopVerdict {
        if !record.isOwn { return .protected(.otherUser) }
        if Self.isSystem(record) { return .protected(.system) }
        if record.pid == ownPID || Self.isSmalti(record.executable) { return .protected(.smalti) }
        if record.run == .zombie { return .protected(.zombie) }
        if attribution.isPaneRoot(record.pid) { return .protected(.paneShell) }
        return .allowed
    }

    private static let systemPIDs: Set<Int32> = [0, 1]
    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]
    private static let smaltiExecutables = [".app/Contents/MacOS/Smalti", ".app/Contents/MacOS/Smalti Dev"]

    private static func isSystem(_ record: ProcessRecord) -> Bool {
        if systemPIDs.contains(record.pid) { return true }
        guard let path = record.executable else { return false }
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    private static func isSmalti(_ executable: String?) -> Bool {
        guard let executable else { return false }
        return smaltiExecutables.contains { executable.hasSuffix($0) }
    }
}
