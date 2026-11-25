/// One tool call an agent is about to make, as its `PreToolUse` hook describes it (spec F7.5).
public struct ToolUse: Equatable, Sendable {
    public let tool: String
    public let command: String?
    public let filePath: String?
    public let searchPath: String?
    public let glob: String?
    public let cwd: String?

    public init(
        tool: String, command: String? = nil, filePath: String? = nil, searchPath: String? = nil, glob: String? = nil,
        cwd: String? = nil
    ) {
        self.tool = tool
        self.command = command
        self.filePath = filePath
        self.searchPath = searchPath
        self.glob = glob
        self.cwd = cwd
    }
}

/// What the guard decided about a tool call.
public enum GuardVerdict: Equatable, Sendable {
    case allow
    case deny(GuardDenial)
    case ask(ApprovalSubject)
}

public enum DenialKind: Equatable, Sendable {
    case secret(path: String)
    case rejected
    case expired
    case unreachable
    case outdatedIntegration
    case paneClosed
    case tooManyPending
}

/// A refusal and the reason the agent reads.
public struct GuardDenial: Equatable, Sendable {
    public let kind: DenialKind
    public let reason: String

    public init(kind: DenialKind, reason: String) {
        self.kind = kind
        self.reason = reason
    }
}

/// A command that waits for the user: the command, redacted, and what the rules found in it.
public struct ApprovalSubject: Equatable, Sendable {
    public let command: String
    public let findings: [GuardFinding]

    public init(command: String, findings: [GuardFinding]) {
        self.command = command
        self.findings = findings
    }

    /// The most severe environment among the findings; production when there is none.
    public var environment: DetectedEnvironment {
        DetectedEnvironment.mostSevere(findings.map(\.environment)) ?? .undetermined
    }

    /// The finding that shows on the card: the first one against the most severe environment.
    public var headline: GuardFinding? {
        findings.first { $0.environment.kind == environment.kind }
    }

    /// The command as a notification quotes it (final review: the command, not the rule).
    public var shortCommand: String {
        command.count > Self.shortCommandLength ? String(command.prefix(Self.shortCommandLength)) + "…" : command
    }

    public static let shortCommandLength = 80

    /// «terraform destroy contra PROD».
    public var summary: String {
        "\(headline?.rule ?? "comando") contra \(environment.label)"
    }
}

/// The texts the agent reads when Smalti refuses (spec F7.5, «Motivos para el agente»).
public enum GuardReasons {
    public static func secret(path: String) -> String {
        "Smalti bloquea la lectura de archivos de secretos (\(path)). No intentes leerlo por otra vía: pide al usuario "
            + "el dato que necesites."
    }

    public static func rejected(_ subject: ApprovalSubject) -> String {
        "El usuario rechazó en Smalti este comando (\(subject.headline?.rule ?? "comando"), contra "
            + "\(subject.environment.label)). No lo reintentes ni busques otra vía; pregunta qué hacer."
    }

    public static func expired(minutes: Int) -> String {
        "Nadie aprobó el comando en Smalti en \(minutes) minutos."
    }

    public static let unreachable = "Smalti no respondió (app cerrada o socket caído): el comando queda bloqueado."
    public static let outdatedIntegration =
        "Este comando necesita la aprobación de Smalti y la integración instalada es antigua: actualízala desde ⌘K."
    public static let cancelled = "Claude canceló la herramienta antes de que el usuario decidiera."
    public static let unreadableInput = "Smalti no pudo leer la petición del hook: la herramienta queda bloqueada."
    public static let paneClosed = "El panel de Smalti se cerró antes de aprobar el comando."
    public static let tooManyPending = "Hay demasiados comandos esperando aprobación en Smalti."
}
