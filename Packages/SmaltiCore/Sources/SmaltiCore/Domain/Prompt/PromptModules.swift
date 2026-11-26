import Foundation

// The eight modules of the board, one type each (spec F5, module table).

struct DirectoryModule: PromptModule {
    let id = PromptModuleID.directory
    let isLocal = true

    func segment(in context: PromptContext) -> PromptSegment? {
        let label = DirectoryLabel.label(directory: context.directory, home: context.home, repoRoot: context.repoRoot)
        return PromptSegment(module: id, icon: .folder, runs: [ColoredText(label, .accent)])
    }
}

struct GitBranchModule: PromptModule {
    let id = PromptModuleID.gitBranch
    let isLocal = false

    func segment(in context: PromptContext) -> PromptSegment? {
        context.branch.map { PromptSegment(module: id, icon: .branch, runs: [ColoredText($0, .ansi(5))]) }
    }
}

struct GitStatusModule: PromptModule {
    let id = PromptModuleID.gitStatus
    let isLocal = false

    /// "●2 +1": modified in amber, staged in green; the space before a piece belongs to it.
    func segment(in context: PromptContext) -> PromptSegment? {
        guard let changes = context.changes else { return nil }
        let pieces = [
            changes.modified > 0 ? ("●\(changes.modified)", SegmentColor.ansi(3)) : nil,
            changes.staged > 0 ? ("+\(changes.staged)", SegmentColor.ansi(2)) : nil,
        ].compactMap { $0 }
        guard !pieces.isEmpty else { return nil }
        let runs = pieces.enumerated().map { index, piece in
            ColoredText(index == 0 ? piece.0 : " " + piece.0, piece.1)
        }
        return PromptSegment(module: id, icon: nil, runs: runs, attachesTo: .gitBranch)
    }
}

struct RuntimeModule: PromptModule {
    let id = PromptModuleID.runtime
    let isLocal = false
    private static let icons: [RuntimeKind: PromptIcon] = [.node: .node, .bun: .bun, .python: .python, .go: .go]

    func segment(in context: PromptContext) -> PromptSegment? {
        context.runtime.map {
            PromptSegment(module: id, icon: Self.icons[$0.kind], runs: [ColoredText($0.version, .secondary)])
        }
    }
}

struct DurationModule: PromptModule {
    let id = PromptModuleID.duration
    let isLocal = true
    private static let threshold = Duration.seconds(2)

    func segment(in context: PromptContext) -> PromptSegment? {
        guard let duration = context.duration, duration >= Self.threshold else { return nil }
        return PromptSegment(module: id, icon: nil, runs: [ColoredText(Self.format(duration), .secondary)])
    }

    /// "4.2s" under a minute, "2m 5s" from there.
    static func format(_ duration: Duration) -> String {
        let milliseconds =
            Int(duration.components.seconds) * 1000
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        guard milliseconds >= 60_000 else {
            let tenths = milliseconds / 100
            return "\(tenths / 10).\(tenths % 10)s"
        }
        let seconds = milliseconds / 1000
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

struct AgentsModule: PromptModule {
    let id = PromptModuleID.agents
    let isLocal = false

    func segment(in context: PromptContext) -> PromptSegment? {
        let agents = context.agents
        let copy = context.copy
        if let text = Self.phrase(agents.waiting, one: copy.agentWaiting, many: copy.agentsWaiting) {
            return PromptSegment(module: id, icon: nil, runs: [ColoredText(text, .waiting)])
        }
        return Self.phrase(agents.failed, one: copy.agentFailed, many: copy.agentsFailed).map {
            PromptSegment(module: id, icon: nil, runs: [ColoredText($0, .failed)])
        }
    }

    private static func phrase(_ names: [String], one: String, many: String) -> String? {
        switch names.count {
        case 0: nil
        case 1: "● \(names[0]) \(one)"
        default: "● \(names.count) \(many)"
        }
    }
}

struct TimeModule: PromptModule {
    let id = PromptModuleID.time
    let isLocal = true

    func segment(in context: PromptContext) -> PromptSegment? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: context.now)
        let text = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return PromptSegment(module: id, icon: .clock, runs: [ColoredText(text, .secondary)])
    }
}

struct CloudModule: PromptModule {
    let id = PromptModuleID.cloud
    let isLocal = false

    func segment(in context: PromptContext) -> PromptSegment? {
        let parts = [context.awsProfile.map { "aws:\($0)" }, context.kubeContext.map { "k8s:\($0)" }].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return PromptSegment(module: id, icon: .cloud, runs: [ColoredText(parts.joined(separator: " "), .ansi(6))])
    }
}
