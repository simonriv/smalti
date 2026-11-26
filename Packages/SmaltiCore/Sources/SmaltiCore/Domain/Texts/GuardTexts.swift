/// F7.7: the guards' words (spec F7.5): rules, environments, the approval card and what the agent reads.
public struct GuardTexts: Sendable, Equatable {
    /// When no finding names the rule.
    public let command: String
    public let against: TextTemplate
    public let environments: [EnvironmentKind: String]
    public let causes: [EnvironmentCause: String]
    public let withKeyword: TextTemplate
    public let noVisibleSQL: TextTemplate
    public let databaseURL: String
    public let providerAPI: TextTemplate
    public let oversized: String
    public let nested: String
    public let counter: TextTemplate
    public let expires: TextTemplate
    public let footer: TextTemplate
    public let secretReason: TextTemplate
    public let rejectedReason: TextTemplate
    public let expiredReason: TextTemplate
    public let unreachable: String
    public let outdatedIntegration: String
    public let cancelled: String
    public let unreadableInput: String
    public let paneClosed: String
    public let tooManyPending: String
    public let unreadableFile: TextTemplate
    public let unwritableFile: TextTemplate

    public static let spanish = GuardTexts(
        command: "comando", against: "{rule} contra {environment}",
        environments: [.production: "PROD", .nonProduction: "QA/desarrollo", .local: "local"],
        causes: [
            .unrecognizedHost: "host no reconocido", .undetermined: "no determinado",
            .linkedProject: "proyecto enlazado",
        ],
        withKeyword: "{program} con {keyword}", noVisibleSQL: "{program} sin SQL visible",
        databaseURL: "URL de base de datos", providerAPI: "API de {provider} ({method})",
        oversized: "comando demasiado largo para revisarlo", nested: "comando anidado demasiado para revisarlo",
        counter: "1 de {count}", expires: "vence en {minutes} min",
        footer: "{approve} aprobar   {reject} rechazar   {expires}",
        secretReason:
            "Smalti bloquea la lectura de archivos de secretos ({path}). No intentes leerlo por otra vía: pide al usuario el dato que necesites.",
        rejectedReason:
            "El usuario rechazó en Smalti este comando ({rule}, contra {environment}). No lo reintentes ni busques otra vía; pregunta qué hacer.",
        expiredReason: "Nadie aprobó el comando en Smalti en {minutes} minutos.",
        unreachable: "Smalti no respondió (app cerrada o socket caído): el comando queda bloqueado.",
        outdatedIntegration:
            "Este comando necesita la aprobación de Smalti y la integración instalada es antigua: actualízala desde ⌘K.",
        cancelled: "Claude canceló la herramienta antes de que el usuario decidiera.",
        unreadableInput: "Smalti no pudo leer la petición del hook: la herramienta queda bloqueada.",
        paneClosed: "El panel de Smalti se cerró antes de aprobar el comando.",
        tooManyPending: "Hay demasiados comandos esperando aprobación en Smalti.",
        unreadableFile: "No se pudo leer {path}: {reason}", unwritableFile: "No se pudo escribir {path}: {reason}")

    public static let english = GuardTexts(
        command: "command", against: "{rule} against {environment}",
        environments: [.production: "PROD", .nonProduction: "QA/development", .local: "local"],
        causes: [
            .unrecognizedHost: "unrecognized host", .undetermined: "undetermined", .linkedProject: "linked project",
        ],
        withKeyword: "{program} with {keyword}", noVisibleSQL: "{program} without visible SQL",
        databaseURL: "database URL", providerAPI: "{provider} API ({method})",
        oversized: "command too long to review", nested: "command nested too deeply to review",
        counter: "1 of {count}", expires: "expires in {minutes} min",
        footer: "{approve} approve   {reject} reject   {expires}",
        secretReason:
            "Smalti blocks reading secret files ({path}). Don’t try to read it another way: ask the user for the value you need.",
        rejectedReason:
            "The user rejected this command in Smalti ({rule}, against {environment}). Don’t retry it or look for another way; ask what to do.",
        expiredReason: "Nobody approved the command in Smalti within {minutes} minutes.",
        unreachable: "Smalti didn’t answer (app closed or socket down): the command stays blocked.",
        outdatedIntegration:
            "This command needs Smalti’s approval and the installed integration is old: update it from ⌘K.",
        cancelled: "Claude cancelled the tool before the user decided.",
        unreadableInput: "Smalti couldn’t read the hook’s request: the tool stays blocked.",
        paneClosed: "The Smalti pane closed before the command was approved.",
        tooManyPending: "Too many commands are waiting for approval in Smalti.",
        unreadableFile: "Couldn’t read {path}: {reason}", unwritableFile: "Couldn’t write {path}: {reason}")
}
