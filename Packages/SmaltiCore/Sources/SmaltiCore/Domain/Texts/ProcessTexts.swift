/// F8: the processes and ports views' words that the domain writes (states, reasons, notices, figures).
public struct ProcessTexts: Sendable, Equatable {
    public let states: [ProcessState: String]
    public let protected: String
    public let local: String
    public let all: String
    /// The pane's name in both views: "web · 2".
    public let paneName: TextTemplate
    /// Why a process cannot be stopped or lowered, as the footer says it.
    public let reasons: [ProtectionReason: TextTemplate]
    public let requested: TextTemplate
    public let waiting: TextTemplate
    public let forced: TextTemplate
    public let lowered: TextTemplate
    public let alreadyLowest: TextTemplate
    public let gone: TextTemplate
    public let notYours: TextTemplate
    public let refused: TextTemplate
    public let unresponsiveHint: String
    public let priorityLevels: [PriorityLevel: TextTemplate]
    public let confirmTitle: TextTemplate
    public let confirmBody: TextTemplate
    public let processes: PluralText
    public let ports: PluralText
    public let openToNetwork: PluralText
    public let hiddenNote: TextTemplate
    public let noMatch: TextTemplate
    public let noPorts: String
    public let noProcesses: String
    public let panesSplit: TextTemplate
    public let listensOn: TextTemplate
    public let goToPane: TextTemplate
    public let stopNamed: TextTemplate
    public let time: TimeTexts

    public static let spanish = ProcessTexts(
        states: [
            .active: "activo", .idle: "en reposo", .stopped: "detenido", .unresponsive: "sin responder",
            .zombie: "zombi",
        ],
        protected: "protegido", local: "solo local", all: "todas", paneName: "{workspace} · {number}",
        reasons: [
            .otherUser: "No se puede detener {name}: es de otro usuario",
            .system: "No se puede detener {name}: es del sistema",
            .smalti: "No se puede detener {name}: es Smalti",
            .paneShell: "{name} es el shell del panel: ciérralo con {close}",
            .zombie: "{name} ya terminó: lo recoge su proceso padre",
        ],
        requested: "Se pidió a {name} que termine", waiting: "Esperando a que {name} termine…",
        forced: "Se forzó el cierre de {name}", lowered: "{name} ahora tiene prioridad {level}",
        alreadyLowest: "{name} ya tiene la prioridad más baja", gone: "{name} ya no existe",
        notYours: "{name} no es tuyo: no se tocó", refused: "El sistema no dejó actuar sobre {name} (error {code})",
        unresponsiveHint: "⌘⌫ para forzar",
        priorityLevels: [
            .high: "alta ({nice})", .normal: "normal ({nice})", .low: "baja ({nice})", .lowest: "muy baja ({nice})",
        ],
        confirmTitle: "¿Forzar el cierre de {name} ({pid})?",
        confirmBody: "No respondió a «Detener» en {seconds} s. Forzarlo (SIGKILL) lo termina sin dejarle guardar nada.",
        processes: PluralText(one: "{count} proceso", other: "{count} procesos"),
        ports: PluralText(one: "{count} puerto", other: "{count} puertos"),
        openToNetwork: PluralText(one: "{count} abierto a la red", other: "{count} abiertos a la red"),
        hiddenNote:
            "Solo tus procesos: {hidden} de otros usuarios o del sistema no se pueden leer sin sudo. Se actualiza cada {seconds} s mientras esta vista está abierta.",
        noMatch: "Nada coincide con «{filter}»", noPorts: "Ningún proceso tuyo escucha en un puerto",
        noProcesses: "Sin procesos que mostrar", panesSplit: "paneles de Smalti {panes} · resto {rest}",
        listensOn: "{addresses} · {scope}", goToPane: "Ir al panel {pane}", stopNamed: "Detener {name} ({pid})",
        time: .spanish)

    public static let english = ProcessTexts(
        states: [
            .active: "active", .idle: "idle", .stopped: "stopped", .unresponsive: "not responding",
            .zombie: "zombie",
        ],
        protected: "protected", local: "local only", all: "all", paneName: "{workspace} · {number}",
        reasons: [
            .otherUser: "Can’t stop {name}: it belongs to another user",
            .system: "Can’t stop {name}: it is part of the system",
            .smalti: "Can’t stop {name}: it is Smalti",
            .paneShell: "{name} is the pane’s shell: close the pane with {close}",
            .zombie: "{name} already ended: its parent process collects it",
        ],
        requested: "Asked {name} to quit", waiting: "Waiting for {name} to quit…",
        forced: "Forced {name} to quit", lowered: "{name} now has {level} priority",
        alreadyLowest: "{name} already has the lowest priority", gone: "{name} no longer exists",
        notYours: "{name} isn’t yours: nothing was touched",
        refused: "The system refused to act on {name} (error {code})",
        unresponsiveHint: "⌘⌫ to force",
        priorityLevels: [
            .high: "high ({nice})", .normal: "normal ({nice})", .low: "low ({nice})", .lowest: "very low ({nice})",
        ],
        confirmTitle: "Force {name} ({pid}) to quit?",
        confirmBody:
            "It did not respond to “Stop” within {seconds} s. Forcing it (SIGKILL) ends it without letting it save anything.",
        processes: PluralText(one: "{count} process", other: "{count} processes"),
        ports: PluralText(one: "{count} port", other: "{count} ports"),
        openToNetwork: PluralText(one: "{count} open to the network", other: "{count} open to the network"),
        hiddenNote:
            "Only your processes: {hidden} belonging to other users or the system cannot be read without sudo. Refreshes every {seconds} s while this view is open.",
        noMatch: "Nothing matches “{filter}”", noPorts: "None of your processes listens on a port",
        noProcesses: "No processes to show", panesSplit: "Smalti panes {panes} · rest {rest}",
        listensOn: "{addresses} · {scope}", goToPane: "Go to pane {pane}", stopNamed: "Stop {name} ({pid})",
        time: .english)
}
