/// `[guards]` in `config.toml` (spec F7.5): the hosts that name an environment and the extra provider APIs.
public struct GuardSettings: Equatable, Sendable {
    public var productionHosts: [String]
    public var nonProductionHosts: [String]
    public var providerAPIHosts: [String]

    public init(productionHosts: [String], nonProductionHosts: [String], providerAPIHosts: [String]) {
        self.productionHosts = productionHosts
        self.nonProductionHosts = nonProductionHosts
        self.providerAPIHosts = providerAPIHosts
    }

    public static let standard = GuardSettings(productionHosts: [], nonProductionHosts: [], providerAPIHosts: [])
}

public enum EnvironmentKind: Int, Comparable, Equatable, Sendable {
    case local
    case nonProduction
    case production

    public static func < (lhs: EnvironmentKind, rhs: EnvironmentKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why the environment is what it is; what the card says after the label.
public enum EnvironmentCause: Equatable, Sendable {
    case listed
    case unrecognizedHost
    case undetermined
    case linkedProject
    case localHost
    case localFlag
}

/// The environment a command acts on, as Smalti shows it («contra PROD · host no reconocido»).
public struct DetectedEnvironment: Equatable, Sendable {
    public let kind: EnvironmentKind
    public let host: String?
    public let cause: EnvironmentCause

    public init(kind: EnvironmentKind, host: String?, cause: EnvironmentCause) {
        self.kind = kind
        self.host = host
        self.cause = cause
    }

    public static let undetermined = DetectedEnvironment(kind: .production, host: nil, cause: .undetermined)

    public var label: String {
        switch kind {
        case .production: "PROD"
        case .nonProduction: "QA/desarrollo"
        case .local: "local"
        }
    }

    public var detail: String? {
        switch cause {
        case .unrecognizedHost: "host no reconocido"
        case .undetermined: "no determinado"
        case .linkedProject: "proyecto enlazado"
        case .listed, .localHost, .localFlag: nil
        }
    }

    /// The production one first; nil when there is none.
    public static func mostSevere(_ environments: [DetectedEnvironment]) -> DetectedEnvironment? {
        environments.max { $0.kind < $1.kind }
    }
}

/// Classifies a host (spec F7.5, «Entorno mostrado»): local, listed, or production when nothing says otherwise.
public enum HostEnvironment {
    public static func classify(host: String?, settings: GuardSettings) -> DetectedEnvironment {
        guard let host else { return .undetermined }
        let name = host.lowercased()
        if isLocal(name) { return DetectedEnvironment(kind: .local, host: host, cause: .localHost) }
        if settings.productionHosts.contains(where: { HostPattern.matches($0, name) }) {
            return DetectedEnvironment(kind: .production, host: host, cause: .listed)
        }
        if settings.nonProductionHosts.contains(where: { HostPattern.matches($0, name) }) {
            return DetectedEnvironment(kind: .nonProduction, host: host, cause: .listed)
        }
        return DetectedEnvironment(kind: .production, host: host, cause: .unrecognizedHost)
    }

    private static let localNames: Set<String> = ["localhost", "::1", "0.0.0.0", "host.docker.internal", ""]

    static func isLocal(_ host: String) -> Bool {
        localNames.contains(host) || host.hasPrefix("127.") || host.hasSuffix(".localhost") || host.hasPrefix("/")
    }
}

/// A host with `*` standing for one or more labels (`*.qa.example.com`), compared without case.
enum HostPattern {
    static func matches(_ pattern: String, _ host: String) -> Bool {
        let patternLabels = pattern.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        let hostLabels = host.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        return matches(patternLabels[...], hostLabels[...])
    }

    private static func matches(_ pattern: ArraySlice<Substring>, _ host: ArraySlice<Substring>) -> Bool {
        guard let first = pattern.first else { return host.isEmpty }
        guard first == "*" else { return host.first == first && matches(pattern.dropFirst(), host.dropFirst()) }
        let rest = pattern.dropFirst()
        return (1...max(host.count, 1)).contains { count in count <= host.count && matches(rest, host.dropFirst(count))
        }
    }
}
