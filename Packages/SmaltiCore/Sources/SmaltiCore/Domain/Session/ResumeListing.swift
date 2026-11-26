import Foundation

/// What a row of "Retomar donde quedaste" says, decided from a snapshot (Reanudar.dc.html, left column).
public enum ResumeTagKind: Sendable {
    /// A coding agent (orange tag).
    case agent
    /// A shell or another program (neutral tag).
    case program
}

public struct ResumeTag: Equatable, Sendable {
    public let text: String
    public let kind: ResumeTagKind

    public init(text: String, kind: ResumeTagKind) {
        self.text = text
        self.kind = kind
    }
}

public struct ResumeRow: Equatable, Sendable {
    public let id: UUID
    public let tag: ResumeTag
    public let title: String
    /// After the title, in the secondary color ("1.240 líneas · 38 comandos", "terminada").
    public let detail: String?
    /// Right-aligned, monospaced ("claude --resume 7f3a…", "scrollback", "pnpm dev").
    public let code: String?
    public let isFinished: Bool
}

public struct ResumeWorkspace: Equatable, Sendable {
    public let name: String
    /// "Dwindle · 3 paneles".
    public let summary: String
    /// Its most urgent agent, for the dot; nil without agents.
    public let status: AgentStateKind?
    public let rows: [ResumeRow]
}

/// The workspaces of one saved window; `title` ("Ventana 1 · 2 workspaces") only when the session had two or more.
public struct ResumeWindow: Equatable, Sendable {
    public let title: String?
    public let workspaces: [ResumeWorkspace]
}

public enum ResumeListing {
    /// Characters of a session id shown before "…".
    static let shortIDLength = 4

    public static func windows(in snapshot: SessionSnapshot, home: WorkingDirectory, harnesses: HarnessRegistry)
        -> [ResumeWindow]
    {
        let isGrouped = snapshot.windows.count >= 2
        return snapshot.windows.enumerated().map { index, window in
            let count = window.workspaces.count
            return ResumeWindow(
                title: isGrouped ? "Ventana \(index + 1) · \(count) \(count == 1 ? "workspace" : "workspaces")" : nil,
                workspaces: workspaces(window.workspaces, home: home, harnesses: harnesses))
        }
    }

    private static func workspaces(
        _ saved: [WorkspaceSnapshot], home: WorkingDirectory, harnesses: HarnessRegistry
    ) -> [ResumeWorkspace] {
        saved.map { workspace in
            let layout = LayoutCatalog.standard.strategyOrDefault(for: LayoutID(rawValue: workspace.layout))
            let count = workspace.panes.count
            return ResumeWorkspace(
                name: workspace.name,
                summary:
                    "\(CommandTexts.spanish.layoutNames[layout.id] ?? layout.id.rawValue) · \(count) \(count == 1 ? "panel" : "paneles")",
                status: AgentStateKind.mostUrgent(workspace.panes.compactMap(\.agent?.lastState)),
                rows: workspace.panes.map { row(for: $0, home: home, harnesses: harnesses) })
        }
    }

    /// `1.240`: thousands grouped with a dot, as written in Spanish.
    public static func grouped(_ value: Int) -> String {
        let digits = Array(String(value))
        return digits.enumerated().reduce(into: "") { text, item in
            if item.offset > 0, (digits.count - item.offset) % 3 == 0 { text.append(".") }
            text.append(item.element)
        }
    }

    private static func row(for pane: PaneSnapshot, home: WorkingDirectory, harnesses: HarnessRegistry) -> ResumeRow {
        let directory =
            (try? WorkingDirectory(path: pane.workingDirectory))?.abbreviated(home: home)
            ?? pane.workingDirectory
        if let agent = pane.agent { return row(for: agent, pane: pane, directory: directory, harnesses: harnesses) }
        let tag = ResumeTag(text: pane.processName ?? "shell", kind: .program)
        if let editor = pane.editor {
            return ResumeRow(
                id: pane.id, tag: tag, title: editor.fileName, detail: "línea \(editor.line)",
                code: "nvim +\(editor.line)", isFinished: false)
        }
        if let relaunch = pane.relaunch {
            return ResumeRow(
                id: pane.id, tag: tag, title: directory, detail: nil, code: relaunch.displayText, isFinished: false)
        }
        return ResumeRow(
            id: pane.id, tag: tag, title: directory, detail: shellDetail(pane),
            code: pane.scrollbackLines > 0 ? "scrollback" : nil, isFinished: false)
    }

    private static func row(
        for agent: AgentSnapshot, pane: PaneSnapshot, directory: String, harnesses: HarnessRegistry
    ) -> ResumeRow {
        let adapter = harnesses.adapter(for: agent.harness)
        let tag = ResumeTag(text: adapter?.displayName ?? agent.harness.rawValue, kind: .agent)
        let isFinished = agent.lastState == .stopped
        guard let sessionID = agent.sessionID else {
            return ResumeRow(
                id: pane.id, tag: tag, title: agent.title ?? directory, detail: continueDetail,
                code: adapter?.continueCommand(), isFinished: false)
        }
        return ResumeRow(
            id: pane.id, tag: tag, title: agent.title ?? directory, detail: isFinished ? "terminada" : nil,
            code: adapter.map { shortResumeCommand(for: agent, id: sessionID, with: $0) }, isFinished: isFinished)
    }

    /// F6: a harness pane without a captured id continues the directory's last session, which may be another one.
    static let continueDetail = "la última del directorio"

    private static func shortResumeCommand(for agent: AgentSnapshot, id: String, with adapter: any HarnessAdapter)
        -> String
    {
        let command = adapter.resumeCommand(sessionID: String(id.prefix(shortIDLength)))
        return id.count > shortIDLength ? command + "…" : command
    }

    private static func shellDetail(_ pane: PaneSnapshot) -> String? {
        var parts: [String] = []
        if pane.scrollbackLines > 0 {
            parts.append("\(grouped(pane.scrollbackLines)) \(pane.scrollbackLines == 1 ? "línea" : "líneas")")
        }
        if pane.commandCount > 0 {
            parts.append("\(grouped(pane.commandCount)) \(pane.commandCount == 1 ? "comando" : "comandos")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
