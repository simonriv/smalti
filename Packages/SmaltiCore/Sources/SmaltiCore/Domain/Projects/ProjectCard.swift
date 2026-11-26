import Foundation

/// One command of a project card: "›" unchanged, "+" added, "−" removed, and where it runs.
public struct ProjectCardLine: Equatable, Sendable {
    public let sign: String
    public let command: String
    public let place: String?
    public let kind: ProjectCommandLine.Kind

    public init(sign: String, command: String, place: String?, kind: ProjectCommandLine.Kind) {
        self.sign = sign
        self.command = command
        self.place = place
        self.kind = kind
    }
}

/// Everything a project card says (mockup `confirm`, `changed`, `replace`).
public struct ProjectCardContent: Equatable, Sendable {
    public let title: String
    public let body: String
    public let lines: [ProjectCardLine]
    /// What else changed, or that only details did; `nil` the first time.
    public let extra: String?
    public let note: String
    public let confirmLabel: String
    public let cancelLabel: String
}

/// The words of F8.5's confirmations, from what the use cases decided.
public enum ProjectCard {
    public struct OpeningContext: Sendable {
        let home: String
        let now: Date
        let texts: ProjectTexts
        let session: SessionTexts
        let layoutNames: [LayoutID: String]

        public init(
            home: String, now: Date, texts: ProjectTexts, session: SessionTexts, layoutNames: [LayoutID: String]
        ) {
            self.home = home
            self.now = now
            self.texts = texts
            self.session = session
            self.layoutNames = layoutNames
        }
    }

    public struct ReplacingContext: Sendable {
        let home: String
        let texts: ProjectTexts

        public init(home: String, texts: ProjectTexts) {
            self.home = home
            self.texts = texts
        }
    }

    public static func opening(_ confirmation: ProjectConfirmation, context: OpeningContext) -> ProjectCardContent {
        let texts = context.texts
        let changes = confirmation.changes
        let body =
            confirmation.approvedAt.map {
                texts.changedSince([
                    "date": RelativeDay.label($0, now: context.now, calendar: .current, texts: context.session)
                ])
            } ?? texts.firstTime
        return ProjectCardContent(
            title: texts.openTitle(["name": confirmation.prepared.name.rawValue]), body: body,
            lines: changes.lines.map(line), extra: extra(confirmation, context: context),
            note: texts.source(["root": ProjectPath.display(confirmation.prepared.root, home: context.home)]),
            confirmLabel: texts.openAndRun, cancelLabel: texts.cancel)
    }

    public static func replacing(_ pending: PendingProjectSave, context: ReplacingContext) -> ProjectCardContent {
        let texts = context.texts
        let lines =
            pending.commands.isEmpty
            ? [ProjectCardLine(sign: "›", command: texts.shellOnly, place: nil, kind: .same)]
            : pending.commands.map { ProjectCardLine(sign: "›", command: $0.command, place: $0.place, kind: .same) }
        return ProjectCardContent(
            title: texts.replaceTitle,
            body: texts.replaceBody(["root": ProjectPath.display(pending.root, home: context.home)]), lines: lines,
            extra: nil, note: texts.replaceNote, confirmLabel: texts.replace, cancelLabel: texts.cancel)
    }

    private static func line(_ line: ProjectCommandLine) -> ProjectCardLine {
        let sign =
            switch line.kind {
            case .same: "›"
            case .added: "+"
            case .removed: "−"
            }
        return ProjectCardLine(sign: sign, command: line.command.command, place: line.command.place, kind: line.kind)
    }

    /// What changed besides the commands, and what Smalti degrades in the file, one per line.
    private static func extra(_ confirmation: ProjectConfirmation, context: OpeningContext) -> String? {
        let warnings = confirmation.warnings.map { warning -> String in
            switch warning {
            case .unknownHarness(let pane, let name):
                context.session.unknownHarness(["pane": String(pane), "name": name])
            case .unknownLayout(let layout): context.session.unknownLayout(["layout": layout])
            }
        }
        let lines = [changed(confirmation.changes, context: context)].compactMap { $0 } + warnings
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func changed(_ changes: ProjectChanges, context: OpeningContext) -> String? {
        if let arrangement = changes.arrangement {
            let name = { (layout: String) in context.layoutNames[LayoutID(rawValue: layout)] ?? layout }
            return context.texts.arrangementChanged([
                "panes": String(arrangement.after.paneCount), "layout": name(arrangement.after.layout),
                "beforePanes": String(arrangement.before.paneCount), "beforeLayout": name(arrangement.before.layout),
            ])
        }
        return changes.hasSameCommands ? context.texts.sameCommands : nil
    }
}
