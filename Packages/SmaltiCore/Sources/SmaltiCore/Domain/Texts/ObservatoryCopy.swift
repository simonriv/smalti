/// F7.7: the observatory's words, as the board writes them in Spanish, and their English.
public struct ObservatoryCopy: Sendable, Equatable {
    public let footnote: String
    public let footnoteWithTelemetry: String
    public let footnoteTelemetryElsewhere: String
    public let sessions: TextTemplate
    public let sessionsFailed: TextTemplate
    public let fromCache: TextTemplate
    public let noInput: String
    public let noOutput: String
    public let peak: TextTemplate
    public let costIncluded: String
    public let costUnpriced: PluralText
    public let states: [AgentStateKind: String]
    public let periods: [ObservatoryPeriod: String]
    /// What cannot be measured without privileges: never 0.
    public let unavailable: String
    public let systemTitle: TextTemplate
    public let splitModel: TextTemplate
    public let splitAgents: TextTemplate
    public let splitRest: TextTemplate
    public let splitPressure: TextTemplate
    public let pressures: [MemoryPressure: String]
    public let ollamaNotRunning: String
    public let noLocalModels: String
    public let loaded: String
    public let onDisk: String
    public let downloaded: TextTemplate
    public let todayTokens: TextTemplate
    public let todayPending: String
    public let activity: TextTemplate
    public let noCompactions: String
    public let compaction: TextTemplate
    public let compactionFreed: TextTemplate
    public let telemetry: TelemetryCopy
    public let time: TimeTexts

    public static let spanish = ObservatoryCopy(
        footnote:
            "Datos: hooks y transcripts de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado.",
        footnoteWithTelemetry:
            "Datos: hooks, transcripts y telemetría de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado.",
        footnoteTelemetryElsewhere: "Telemetría de Claude Code configurada fuera de Smalti: no se recibe aquí.",
        sessions: "{working} trabajando · {waiting} esperando", sessionsFailed: " · {failed} error",
        fromCache: "{percent} desde caché", noInput: "sin entrada", noOutput: "sin salida",
        peak: "pico {count}/min · {clock}", costIncluded: "estimado · incluido en tu plan",
        costUnpriced: PluralText(
            one: "estimado · sin precio para {count} modelo", other: "estimado · sin precio para {count} modelos"),
        states: [.working: "trabajando", .waiting: "te espera", .failed: "error", .stopped: "detenida"],
        periods: [.today: "Hoy", .lastSevenDays: "7 días", .lastThirtyDays: "30 días"],
        unavailable: "no disponible", systemTitle: "Sistema · {machine}", splitModel: "modelo {value}",
        splitAgents: "agentes {value}", splitRest: "resto {value} GB", splitPressure: "presión {value}",
        pressures: [.normal: "normal", .media: "media", .alta: "alta"],
        ollamaNotRunning: "Ollama no está corriendo", noLocalModels: "Sin modelos locales", loaded: "cargado",
        onDisk: "en disco", downloaded: "descargado {ago}", todayTokens: "hoy {count} tokens", todayPending: "hoy …",
        activity: "Actividad · {label}", noCompactions: "Sin compactaciones", compaction: "Compactación {ago}",
        compactionFreed: "Compactación {ago} · liberó {percent}% del contexto", telemetry: .spanish, time: .spanish)

    public static let english = ObservatoryCopy(
        footnote:
            "Data: Claude Code hooks and transcripts, OpenCode’s database and Ollama’s local API. Cost is estimated.",
        footnoteWithTelemetry:
            "Data: Claude Code hooks, transcripts and telemetry, OpenCode’s database and Ollama’s local API. Cost is estimated.",
        footnoteTelemetryElsewhere: "Claude Code telemetry is configured outside Smalti: it isn’t received here.",
        sessions: "{working} working · {waiting} waiting", sessionsFailed: " · {failed} failed",
        fromCache: "{percent} from cache", noInput: "no input", noOutput: "no output",
        peak: "peak {count}/min · {clock}", costIncluded: "estimated · included in your plan",
        costUnpriced: PluralText(
            one: "estimated · no price for {count} model", other: "estimated · no price for {count} models"),
        states: [.working: "working", .waiting: "waiting", .failed: "error", .stopped: "stopped"],
        periods: [.today: "Today", .lastSevenDays: "7 days", .lastThirtyDays: "30 days"],
        unavailable: "unavailable", systemTitle: "System · {machine}", splitModel: "model {value}",
        splitAgents: "agents {value}", splitRest: "other {value} GB", splitPressure: "pressure {value}",
        pressures: [.normal: "normal", .media: "medium", .alta: "high"],
        ollamaNotRunning: "Ollama isn’t running", noLocalModels: "No local models", loaded: "loaded",
        onDisk: "on disk", downloaded: "downloaded {ago}", todayTokens: "today {count} tokens", todayPending: "today …",
        activity: "Activity · {label}", noCompactions: "No compactions", compaction: "Compacted {ago}",
        compactionFreed: "Compacted {ago} · freed {percent}% of the context", telemetry: .english, time: .english)
}

/// F7.7: the telemetry line of the session detail (spec F7).
public struct TelemetryCopy: Sendable, Equatable {
    public let title: String
    public let since: TextTemplate
    public let requests: PluralText
    public let median: TextTemplate
    /// "1,4 s" in Spanish, "1.4 s" in English.
    public let decimalSeparator: String
    public let noErrors: String
    public let errors: PluralText
    public let cost: TextTemplate

    public static let spanish = TelemetryCopy(
        title: "Telemetría", since: "desde {clock}",
        requests: PluralText(one: "{count} petición", other: "{count} peticiones"), median: "mediana {duration}",
        decimalSeparator: ",", noErrors: "sin errores de API",
        errors: PluralText(one: "{count} error de API", other: "{count} errores de API"),
        cost: "{usd} según Claude Code")

    public static let english = TelemetryCopy(
        title: "Telemetry", since: "since {clock}",
        requests: PluralText(one: "{count} request", other: "{count} requests"), median: "median {duration}",
        decimalSeparator: ".", noErrors: "no API errors",
        errors: PluralText(one: "{count} API error", other: "{count} API errors"),
        cost: "{usd} according to Claude Code")
}
