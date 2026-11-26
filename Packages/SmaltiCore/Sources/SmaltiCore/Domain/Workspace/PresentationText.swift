extension Workspace {
    /// Status bar line, as in Main.dc.html: "solen · 3 paneles · dwindle".
    public func statusLine(texts: StatusTexts) -> String {
        "\(name) · \(texts.panes(panes.count)) · \(texts.layoutNames[layout.id] ?? layout.id.rawValue)"
    }
}

import Foundation

/// How a header detail is coloured: amber waiting, red failed, secondary otherwise.
public enum HeaderTone: Sendable {
    case waiting, failed, secondary
}

/// "te espera · 2m", "error · 3m" or the session's lifetime ("1h 12m"), right of the directory (Main.dc.html).
public struct HeaderDetail: Equatable, Sendable {
    public let text: String
    public let tone: HeaderTone

    public init(text: String, tone: HeaderTone) {
        self.text = text
        self.tone = tone
    }

    static func of(_ agent: AgentSession?, now: Date, texts: StatusTexts) -> HeaderDetail? {
        guard let agent else { return nil }
        let elapsed = { (since: Date) in ["elapsed": ElapsedText.short(since: since, now: now)] }
        switch agent.state {
        case .waiting(let since, .approval):
            return HeaderDetail(text: texts.waitingForApproval(elapsed(since)), tone: .waiting)
        case .waiting(let since, _):
            return HeaderDetail(text: texts.waiting(elapsed(since)), tone: .waiting)
        case .failed(let since, _):
            return HeaderDetail(text: texts.failed(elapsed(since)), tone: .failed)
        case .working: return HeaderDetail(text: ElapsedText.short(since: agent.startedAt, now: now), tone: .secondary)
        case .stopped: return nil
        }
    }
}

/// What a header needs besides its pane.
public struct HeaderContext: Sendable {
    public let keymap: Keymap
    public let home: WorkingDirectory
    public let now: Date
    /// Model family and context load per agent session, from the observatory (F3); empty until it reports.
    public var agentDetails: [String: PaneAgentDetail] = [:]
    /// F5 "Solo símbolo": the prompt's context per pane, shown instead of the directory.
    public var promptHeaders: [PaneID: String] = [:]
    /// F7.7: the words of the interface's language.
    public let texts: StatusTexts

    public init(keymap: Keymap, home: WorkingDirectory, now: Date, texts: StatusTexts) {
        self.keymap = keymap
        self.home = home
        self.now = now
        self.texts = texts
    }
}

/// What a pane header shows: the agent's state dot, the foreground process (or the title), the directory relative to
/// home, the agent's detail and the shortcut `⌘1`…`⌘9` (the boards' `⌥N` is replaced: ⌥ types characters on the
/// Latin American layout).
public struct PaneHeaderContent: Equatable, Sendable {
    public let process: String
    public let directory: String
    /// nil without an agent: the neutral dot of F1.
    public let status: AgentStateKind?
    public let detail: HeaderDetail?
    public let shortcut: String
    /// "ctx 41%" before the lifetime, only while the agent works and its load is known (Main.dc.html).
    public private(set) var context: ContextLoad?

    public init(process: String, directory: String, status: AgentStateKind?, detail: HeaderDetail?, shortcut: String) {
        self.process = process
        self.directory = directory
        self.status = status
        self.detail = detail
        self.shortcut = shortcut
    }

    /// `index` is the pane's 1-based position when it has a shortcut (1…9), nil otherwise.
    public init(_ pane: Pane, index: Int?, context: HeaderContext) {
        let agentDetail = pane.agent.flatMap { context.agentDetails[$0.sessionID] }
        let directory = pane.workingDirectory.abbreviated(home: context.home)
        let shown = context.promptHeaders[pane.id] ?? agentDetail?.family.map { "\(directory) · \($0)" } ?? directory
        self.init(
            process: pane.headerName, directory: shown,
            status: pane.agent?.state.kind, detail: HeaderDetail.of(pane.agent, now: context.now, texts: context.texts),
            shortcut: index.flatMap { context.keymap.chord(for: .paneFocus($0))?.display } ?? "")
        if pane.agent?.state.kind == .working, let load = agentDetail?.context, load != .unavailable {
            self.context = load
        }
    }
}

/// One counter of the workspace strip: "2 trabajando", "1 te espera", "1 error". Counters at zero are not shown.
public struct StripCounter: Equatable, Sendable {
    public let kind: AgentStateKind
    public let text: String

    public init(kind: AgentStateKind, text: String) {
        self.kind = kind
        self.text = text
    }

    public static func counters(_ counts: AgentCounts, texts: StatusTexts) -> [StripCounter] {
        [(AgentStateKind.working, counts.working), (.waiting, counts.waiting), (.failed, counts.failed)]
            .filter { $0.1 > 0 }
            .map { StripCounter(kind: $0.0, text: "\($0.1) \(texts.counters[$0.0] ?? "")") }
    }
}
