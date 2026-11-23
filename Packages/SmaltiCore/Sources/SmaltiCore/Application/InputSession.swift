import Foundation

/// The fixed suggestions for the word at the cursor, and whether generators will add more: the menu waits for
/// them before falling back, inserting a single match or showing.
public struct CompletionResult: Equatable, Sendable {
    public let items: [Suggestion]
    public let hasGenerators: Bool

    public init(items: [Suggestion], hasGenerators: Bool) {
        self.items = items
        self.hasGenerators = hasGenerators
    }
}

/// F4's use cases for every pane: suggest the rest of the line, complete the word at the cursor, search the
/// history, and record each command. One actor holds the history index for the whole app, off the main thread.
public actor InputSession {
    public struct Ports: Sendable {
        let history: any CommandHistory
        let project: any ProjectContext
        let completions: any CompletionProvider
        let predictor: any PredictionProvider

        public init(
            history: any CommandHistory, project: any ProjectContext, completions: any CompletionProvider,
            predictor: any PredictionProvider
        ) {
            self.history = history
            self.project = project
            self.completions = completions
            self.predictor = predictor
        }
    }

    private struct Running {
        let command: String
        let directory: String
        let start: Date
    }

    private let ports: Ports
    private let settings: InputSettings
    private let clock: @Sendable () -> Date
    private var index: HistoryIndex
    private var hasStarted = false
    private var isLoaded = false
    /// Commands recorded before the history finished loading, to keep after the loaded ones.
    private var recordedWhileLoading: [HistoryEntry] = []
    private var running: [PaneID: Running] = [:]
    private var previous: [PaneID: HistoryEntry] = [:]
    /// The last failure to read or write the history; the app reports it once.
    public private(set) var lastError: HistoryError?
    /// The last generator that failed; the menu keeps what it has.
    public private(set) var lastCompletionError: CompletionError?

    private enum SpecLookup {
        /// No spec for the command, or completions are off: zsh runs the user's own Tab.
        case unknownCommand
        /// The command has a spec; nil when the cursor is somewhere it offers nothing.
        case known(CompletionTarget?)
    }

    public init(ports: Ports, settings: InputSettings, clock: @escaping @Sendable () -> Date) {
        self.ports = ports
        self.settings = settings
        self.clock = clock
        index = HistoryIndex(entries: [], limit: settings.historyLimit)
    }

    /// Loads the history once; a failure leaves it empty and kept in `lastError`.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        var loaded: [HistoryEntry] = []
        do {
            loaded = try await ports.history.load()
        } catch {
            lastError = error
        }
        index = HistoryIndex(entries: loaded + recordedWhileLoading, limit: settings.historyLimit)
        recordedWhileLoading = []
        isLoaded = true
    }

    public var specCommands: [String] {
        get async {
            guard settings.isEnabled, settings.hasCompletions else { return [] }
            return await ports.completions.commands.sorted()
        }
    }

    /// SuggestForLine: the ghost text after the cursor, or "" for none.
    public func suggest(_ line: InputLine, pane: PaneID, directory: String) async -> String {
        guard settings.isEnabled, settings.hasPredictions else { return "" }
        // The snapshot first: the index read after the wait is the current one, and is not copied across it.
        let project = await ports.project.snapshot(of: directory)
        let context = PredictionContext(
            line: line, directory: directory, previous: previous[pane], index: index, project: project, now: clock())
        return ports.predictor.predict(context)?.suffix ?? ""
    }

    /// CompleteLine: the fixed suggestions and template paths for the word at the cursor, ranked, and whether
    /// generators are pending; nil when the command has no spec (zsh then runs the user's own Tab).
    public func complete(_ line: InputLine, directory: String) async -> CompletionResult? {
        guard case .known(let found) = await lookup(line) else { return nil }
        guard let target = found else { return CompletionResult(items: [], hasGenerators: false) }
        let prefix = line.wordBeforeCursor
        let paths = await templatePaths(for: target, prefix: prefix, directory: directory)
        let items = CompletionEngine.rank(
            CompletionEngine.suggestions(for: target) + paths, prefix: prefix, history: index)
        return CompletionResult(items: items, hasGenerators: !Self.generators(of: target).isEmpty)
    }

    /// The generators' suggestions for the word at the cursor, ranked; a failing generator adds nothing.
    public func generated(for line: InputLine, directory: String) async -> [Suggestion] {
        guard case .known(let found) = await lookup(line), let target = found else { return [] }
        let tokens = line.currentCommand.map(\.text)
        var items: [Suggestion] = []
        for generator in Self.generators(of: target) {
            do {
                items += try await ports.completions.generate(generator, tokens: tokens, in: directory)
            } catch {
                lastCompletionError = error
            }
        }
        return CompletionEngine.rank(items, prefix: line.wordBeforeCursor, history: index)
    }

    /// True while no command was ever recorded: ⌃R then says "Historial vacío", not "Sin coincidencias".
    public var isHistoryEmpty: Bool { index.count == 0 }

    /// SearchHistory (⌃R).
    public func search(_ query: String, scope: HistoryScope) -> [HistoryHit] {
        HistorySearch.search(query, scope: scope, in: index)
    }

    /// RecordCommand, first half: zsh's `preexec`.
    public func began(_ command: String, pane: PaneID, directory: String) {
        running[pane] = Running(command: command, directory: directory, start: clock())
    }

    /// RecordCommand, second half: zsh's `precmd`. Commands the secret filter flags are never kept, and the pane
    /// then has no previous command to predict from.
    public func finished(pane: PaneID, exit: Int) async {
        guard let command = running.removeValue(forKey: pane) else { return }
        guard !SecretFilter.isSensitive(command.command) else {
            previous[pane] = nil
            return
        }
        let now = clock()
        let entry = HistoryEntry(
            command: command.command, directory: command.directory, exit: exit,
            duration: now.timeIntervalSince(command.start), date: now, pane: pane)
        index.append(entry)
        if !isLoaded { recordedWhileLoading.append(entry) }
        previous[pane] = entry
        do {
            try await ports.history.append(entry)
        } catch {
            lastError = error
        }
    }

    private func lookup(_ line: InputLine) async -> SpecLookup {
        guard settings.isEnabled, settings.hasCompletions, let command = line.currentCommand.first?.text,
            let spec = await ports.completions.spec(for: command)
        else { return .unknownCommand }
        return .known(CompletionEngine.target(for: line, spec: spec))
    }

    private func templatePaths(for target: CompletionTarget, prefix: String, directory: String) async -> [Suggestion] {
        let templates = Self.argument(of: target)?.templates ?? []
        guard !templates.isEmpty else { return [] }
        return await ports.completions.paths(
            matching: prefix, in: directory, foldersOnly: !templates.contains(.filepaths))
    }

    private static func generators(of target: CompletionTarget) -> [GeneratorID] {
        argument(of: target)?.generators ?? []
    }

    private static func argument(of target: CompletionTarget) -> ArgSpec? {
        switch target {
        case .subcommandOrOption(_, let spec): spec.args.first
        case .optionValue(let option, _): option.args.first
        case .argument(let arg, _): arg
        }
    }
}
