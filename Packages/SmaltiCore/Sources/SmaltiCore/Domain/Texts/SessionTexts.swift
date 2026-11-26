/// F7.7: resuming, saved and shared layouts, the agents' session search and the ⌃R history.
public struct SessionTexts: Sendable, Equatable {
    public let window: TextTemplate
    public let workspaces: PluralText
    public let panes: PluralText
    public let layoutNames: [LayoutID: String]
    public let editorLine: TextTemplate
    public let finished: String
    public let continueDetail: String
    /// `{n}` is the count with its thousands grouped.
    public let lines: PluralText
    public let commands: PluralText
    public let thousandsSeparator: String
    public let tokens: TextTemplate
    public let notFound: TextTemplate
    public let saveFailed: TextTemplate
    public let savedByNewer: TextTemplate
    public let archiveNewer: TextTemplate
    public let keptNewer: TextTemplate
    public let archiveNotFound: TextTemplate
    public let unreadable: TextTemplate
    public let unwritable: TextTemplate
    public let layoutErrors: SharedLayoutErrorTexts
    public let terminal: TerminalTexts
    public let located: TextTemplate
    public let importTitle: TextTemplate
    public let opensOnlyShells: String
    public let willRun: TextTemplate
    public let folderPrompt: TextTemplate
    public let unknownHarness: TextTemplate
    public let unknownLayout: TextTemplate
    public let folderMissing: TextTemplate
    public let unavailable: TextTemplate
    public let cannotFork: TextTemplate
    public let paneFailed: TextTemplate
    public let noAdapter: TextTemplate
    public let allHarnesses: String
    public let noSessions: String
    public let noMatches: String
    public let readFailed: TextTemplate
    public let storeMissing: TextTemplate
    public let unknownSchema: TextTemplate
    public let timedOut: String
    public let today: String
    public let yesterday: String
    public let weekdays: [String]
    public let months: [String]
    public let dayMonth: TextTemplate
    public let historyMinutes: TextTemplate
    public let historyHours: TextTemplate
    public let historyDays: TextTemplate

    public static let spanish = SessionTexts(
        window: "Ventana {number} · {workspaces}",
        workspaces: PluralText(one: "{count} workspace", other: "{count} workspaces"),
        panes: PluralText(one: "{count} panel", other: "{count} paneles"),
        layoutNames: CommandTexts.spanish.layoutNames,
        editorLine: "línea {line}", finished: "terminada", continueDetail: "la última del directorio",
        lines: PluralText(one: "{n} línea", other: "{n} líneas"),
        commands: PluralText(one: "{n} comando", other: "{n} comandos"), thousandsSeparator: ".", tokens: "{n} tokens",
        notFound: "no hay ningún layout guardado como «{name}»", saveFailed: "no se pudo guardar {file} ({reason})",
        savedByNewer: "{file} lo guardó una versión más nueva de Smalti (formato {version})",
        archiveNewer: "{file}: guardado por una versión más nueva de Smalti (formato {version})",
        keptNewer:
            "La sesión la guardó una versión más nueva de Smalti (formato {version}): esta no la abre ni la sobrescribe",
        archiveNotFound: "{name}: no se encontró", unreadable: "no se pudo leer {path} ({reason})",
        unwritable: "no se pudo escribir {path} ({reason})", layoutErrors: .spanish, terminal: .spanish,
        located: "{command} en {place}",
        importTitle: "¿Importar el layout “{name}”?", opensOnlyShells: "Al abrirlo solo abrirá shells.",
        willRun: "Al abrirlo ejecutará: {commands}", folderPrompt: "Elige la carpeta de “{name}” en este Mac",
        unknownHarness: "El panel {pane} usa un harness desconocido ({name}): se abrirá como shell.",
        unknownLayout: "Layout desconocido ({layout}): se usará Dwindle.",
        folderMissing: "La carpeta de la sesión ya no existe: {path}",
        unavailable: "{harness} no está disponible en este Mac", cannotFork: "{harness} no permite bifurcar sesiones",
        paneFailed: "{directory}: no se pudo abrir el panel ({error})",
        noAdapter: "{harness}: harness sin adaptador, no se reanuda {session}", allHarnesses: "Todas",
        noSessions: "No hay sesiones de agentes en este Mac", noMatches: "Sin sesiones que coincidan",
        readFailed: "No se pudo leer {harness}: {reason}", storeMissing: "no existe {path}",
        unknownSchema: "esquema desconocido (falta {missing})", timedOut: "tardó demasiado", today: "hoy",
        yesterday: "ayer", weekdays: ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"],
        months: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"],
        dayMonth: "{day} {month}", historyMinutes: "hace {n} min", historyHours: "hace {n} h",
        historyDays: "hace {n} días")

    public static let english = SessionTexts(
        window: "Window {number} · {workspaces}",
        workspaces: PluralText(one: "{count} workspace", other: "{count} workspaces"),
        panes: PluralText(one: "{count} pane", other: "{count} panes"), layoutNames: CommandTexts.english.layoutNames,
        editorLine: "line {line}", finished: "finished", continueDetail: "the folder’s last one",
        lines: PluralText(one: "{n} line", other: "{n} lines"),
        commands: PluralText(one: "{n} command", other: "{n} commands"), thousandsSeparator: ",", tokens: "{n} tokens",
        notFound: "no layout is saved as “{name}”", saveFailed: "couldn’t save {file} ({reason})",
        savedByNewer: "{file} was saved by a newer Smalti (format {version})",
        archiveNewer: "{file}: saved by a newer Smalti (format {version})",
        keptNewer: "A newer Smalti saved the session (format {version}): this one neither opens nor overwrites it",
        archiveNotFound: "{name}: not found",
        unreadable: "couldn’t read {path} ({reason})", unwritable: "couldn’t write {path} ({reason})",
        layoutErrors: .english, terminal: .english, located: "{command} in {place}",
        importTitle: "Import the layout “{name}”?",
        opensOnlyShells: "Opening it will only open shells.", willRun: "Opening it will run: {commands}",
        folderPrompt: "Choose the folder for “{name}” on this Mac",
        unknownHarness: "Pane {pane} uses an unknown harness ({name}): it will open as a shell.",
        unknownLayout: "Unknown layout ({layout}): Dwindle will be used.",
        folderMissing: "The session’s folder no longer exists: {path}",
        unavailable: "{harness} isn’t available on this Mac",
        cannotFork: "{harness} can’t fork sessions", paneFailed: "{directory}: couldn’t open the pane ({error})",
        noAdapter: "{harness}: no adapter for this harness, {session} isn’t resumed", allHarnesses: "All",
        noSessions: "No agent sessions on this Mac", noMatches: "No matching sessions",
        readFailed: "Couldn’t read {harness}: {reason}", storeMissing: "{path} doesn’t exist",
        unknownSchema: "unknown schema ({missing} is missing)", timedOut: "took too long", today: "today",
        yesterday: "yesterday", weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
        months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
        dayMonth: "{month} {day}", historyMinutes: "{n} min ago", historyHours: "{n} h ago",
        historyDays: "{n} days ago")
}

/// Why a shared layout file is not valid (spec F7).
public struct SharedLayoutErrorTexts: Sendable, Equatable {
    public let unsupportedFormat: TextTemplate
    public let newerFormat: TextTemplate
    public let invalidName: TextTemplate
    public let noPanes: String
    public let tooManyPanes: TextTemplate
    public let treeMismatch: TextTemplate
    public let untypeableCommand: TextTemplate
    public let emptyCommand: TextTemplate
    public let escapingDirectory: TextTemplate
    public let tooLarge: TextTemplate
    public let notJSON: TextTemplate
    public let ambiguousPane: TextTemplate
    public let invalidEditor: TextTemplate
    public let invalidTree: String
    public let invalidRoot: TextTemplate
    public let jsonMissingKey: TextTemplate
    public let jsonInvalidValue: TextTemplate
    public let jsonInvalid: String

    public static let spanish = SharedLayoutErrorTexts(
        unsupportedFormat: "formato {format} no compatible con esta versión de Smalti",
        newerFormat: "lo exportó una versión más nueva de Smalti (formato {format}); actualiza Smalti para importarlo",
        invalidName: "el nombre «{name}» no es válido ({reason})", noPanes: "no tiene paneles",
        tooManyPanes: "tiene {count} paneles; el máximo es {maximum}",
        treeMismatch: "su árbol tiene {leaves} paneles y la lista {panes}",
        untypeableCommand: "el comando del panel {pane} tiene caracteres de control",
        emptyCommand: "el comando del panel {pane} está vacío",
        escapingDirectory: "la ruta «{path}» del panel {pane} sale de la carpeta del layout",
        tooLarge: "pesa {bytes} bytes; el máximo es {maximum}", notJSON: "no es un layout de Smalti ({reason})",
        ambiguousPane: "el panel {pane} indica más de un programa que abrir",
        invalidEditor: "el archivo o la línea del editor del panel {pane} no son válidos",
        invalidTree: "su árbol no coloca cada panel una sola vez",
        invalidRoot: "la carpeta «{root}» no es una ruta absoluta ni empieza por ~",
        jsonMissingKey: "falta «{key}»", jsonInvalidValue: "valor no válido en «{path}»", jsonInvalid: "JSON no válido")

    public static let english = SharedLayoutErrorTexts(
        unsupportedFormat: "format {format} isn’t supported by this version of Smalti",
        newerFormat: "a newer Smalti exported it (format {format}); update Smalti to import it",
        invalidName: "the name “{name}” isn’t valid ({reason})", noPanes: "it has no panes",
        tooManyPanes: "it has {count} panes; the maximum is {maximum}",
        treeMismatch: "its tree has {leaves} panes and its list {panes}",
        untypeableCommand: "pane {pane}’s command has control characters",
        emptyCommand: "pane {pane}’s command is empty",
        escapingDirectory: "the path “{path}” of pane {pane} leaves the layout’s folder",
        tooLarge: "it weighs {bytes} bytes; the maximum is {maximum}", notJSON: "it isn’t a Smalti layout ({reason})",
        ambiguousPane: "pane {pane} names more than one program to open",
        invalidEditor: "pane {pane}’s editor file or line isn’t valid",
        invalidTree: "its tree doesn’t place each pane exactly once",
        invalidRoot: "the folder “{root}” is neither an absolute path nor starts with ~",
        jsonMissingKey: "“{key}” is missing", jsonInvalidValue: "invalid value at “{path}”", jsonInvalid: "invalid JSON"
    )

    func describe(_ problem: LayoutJSONProblem) -> String {
        switch problem {
        case .missingKey(let key): jsonMissingKey(["key": key])
        case .invalidValue(let path): jsonInvalidValue(["path": path])
        case .invalid: jsonInvalid
        case .other(let description): description
        }
    }
}
