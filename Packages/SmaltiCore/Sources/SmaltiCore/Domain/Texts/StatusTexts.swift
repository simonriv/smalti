/// F7.7: the status bar, pane headers, the workspace strip, notifications and the resume screen's "when".
public struct StatusTexts: Sendable {
    public let panes: PluralText
    /// The layout's short name at the end of the status line.
    public let layoutNames: [LayoutID: String]
    public let waitingForApproval: TextTemplate
    public let waiting: TextTemplate
    public let failed: TextTemplate
    /// The strip's counters: "2 trabajando", "1 te espera", "1 error".
    public let counters: [AgentStateKind: String]
    public let asksPermission: String
    public let asksPermissionFor: TextTemplate
    public let turnFinished: String
    public let failure: TextTemplate
    public let approval: TextTemplate
    public let closedToday: TextTemplate
    public let closedLastNight: TextTemplate
    public let closedYesterday: TextTemplate
    public let closedOn: TextTemplate
    /// Sunday first, as `Calendar` numbers weekdays.
    public let weekdays: [String]

    public static let spanish = StatusTexts(
        panes: PluralText(one: "{count} panel", other: "{count} paneles"),
        layoutNames: [.dwindle: "dwindle", .columns: "columnas", .master: "maestro"],
        waitingForApproval: "espera tu aprobación · {elapsed}", waiting: "te espera · {elapsed}",
        failed: "error · {elapsed}", counters: [.working: "trabajando", .waiting: "te espera", .failed: "error"],
        asksPermission: "pide permiso", asksPermissionFor: "pide permiso para `{summary}`",
        turnFinished: "terminó y te espera", failure: "error: {message}",
        approval: "Aprobación: `{command}` contra {environment}", closedToday: "hoy a las {time}",
        closedLastNight: "anoche a las {time}", closedYesterday: "ayer a las {time}",
        closedOn: "el {weekday} {day} a las {time}", weekdays: ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"])

    public static let english = StatusTexts(
        panes: PluralText(one: "{count} pane", other: "{count} panes"),
        layoutNames: [.dwindle: "dwindle", .columns: "columns", .master: "master"],
        waitingForApproval: "waiting for approval · {elapsed}", waiting: "waiting · {elapsed}",
        failed: "error · {elapsed}", counters: [.working: "working", .waiting: "waiting", .failed: "error"],
        asksPermission: "asks for permission", asksPermissionFor: "asks for permission to `{summary}`",
        turnFinished: "finished and is waiting for you", failure: "error: {message}",
        approval: "Approval: `{command}` against {environment}", closedToday: "today at {time}",
        closedLastNight: "last night at {time}", closedYesterday: "yesterday at {time}",
        closedOn: "on {weekday} {day} at {time}", weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
}
