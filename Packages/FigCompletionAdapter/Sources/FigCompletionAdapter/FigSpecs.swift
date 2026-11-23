import Foundation
import JavaScriptCore
import SmaltiCore

/// Completion specs in Fig's format, run with JavaScriptCore: the bundled ones (`Specs/`, vendored by
/// `scripts/fig/vendor_specs.py`) and the user's own in `~/.config/smalti/completions/*.js`, which win.
///
/// Each spec loads once into its own `JSContext` on one virtual machine; this actor serializes every use of them. A
/// user spec reloads when its file changes, and a broken one falls back to the bundled spec. A script generator's
/// output is cached for `cacheLifetime` per evaluated script and directory; a custom one per tokens and directory.
public actor FigSpecs: CompletionProvider {
    public static let cacheLifetime: TimeInterval = 30

    private struct Loaded {
        let spec: CompletionSpec
        /// The user file's modification date when it was loaded; nil for a bundled spec.
        let userVersion: Date?
    }

    private struct Cached<Value> {
        let date: Date
        let value: Value
    }

    private let bundled: URL?
    private let bundledNames: [String: String]
    private let bundledCommands: [String]
    private let user: URL
    private let runner: GeneratorRunner
    private let clock: @Sendable () -> Date
    private let machine = JSVirtualMachine()
    private var loaded: [String: Loaded] = [:]
    /// Names that failed to load, with the user file version that failed (nil: no user file).
    private var failed: [String: Date?] = [:]
    private var generators: [GeneratorID: JSValue] = [:]
    private var outputs: [String: Cached<String>] = [:]
    private var results: [String: Cached<[Suggestion]>] = [:]
    /// The last spec that failed to load or generator that failed to run.
    public private(set) var lastError: CompletionError?

    public init(user: URL, runner: GeneratorRunner, clock: @escaping @Sendable () -> Date = { Date() }) {
        let bundled = Bundle.module.url(forResource: "Specs", withExtension: nil)
        let manifest = bundled.flatMap(Self.manifest(in:))
        self.bundled = bundled
        bundledNames = manifest?.specs ?? [:]
        bundledCommands = manifest?.commands ?? []
        self.user = user
        self.runner = runner
        self.clock = clock
    }

    public var commands: [String] {
        let userCommands = ((try? FileManager.default.contentsOfDirectory(atPath: userPath)) ?? [])
            .filter { $0.hasSuffix(".js") }.map { String($0.dropLast(3)) }
        return Array(Set(bundledCommands + userCommands)).sorted()
    }

    public func spec(for command: String) async -> CompletionSpec? {
        guard Self.isValidName(command) else { return nil }
        let version = userVersion(of: command)
        if let loaded = loaded[command], loaded.userVersion == version { return loaded.spec }
        if let failedVersion = failed[command], failedVersion == version { return nil }
        guard let object = module(command, userVersion: version) else {
            failed[command] = version
            return nil
        }
        // Each `loadSpec` gets a context of its own: minified modules share short global names.
        var translator = FigSpecTranslator(specName: command) { name in self.module(name, userVersion: nil) }
        let spec = translator.spec(from: object)
        generators.merge(translator.generators) { _, new in new }
        loaded[command] = Loaded(spec: spec, userVersion: version)
        failed[command] = nil
        return spec
    }

    public func generate(_ generator: GeneratorID, tokens: [String], in directory: String) async throws(CompletionError)
        -> [Suggestion]
    {
        guard let value = generators[generator] else {
            throw CompletionError(command: generator.spec, cause: "unknown generator \(generator.ordinal)")
        }
        do {
            return try await run(value, request: GeneratorRequest(tokens: tokens, directory: directory, id: generator))
        } catch {
            lastError = error
            throw error
        }
    }

    public func paths(matching prefix: String, in directory: String, foldersOnly: Bool) async -> [Suggestion] {
        PathListing(prefix: prefix, directory: directory).entries(foldersOnly: foldersOnly)
    }

    private var userPath: String { user.path(percentEncoded: false) }

    /// Evaluates a spec module in a fresh context and returns its default export, or nil (remembering why). A
    /// user spec that fails falls back to the bundled one of the same name.
    private func module(_ name: String, userVersion: Date?) -> JSValue? {
        if userVersion != nil, let own = try? String(contentsOf: userFile(name), encoding: .utf8) {
            if let object = evaluate(own, named: name) { return object }
        }
        guard let bundled, let file = bundledNames[name],
            let text = try? String(contentsOf: bundled.appending(path: file), encoding: .utf8)
        else { return nil }
        return evaluate(text, named: name)
    }

    private func evaluate(_ source: String, named name: String) -> JSValue? {
        guard let context = JSContext(virtualMachine: machine) else { return nil }
        // Keep JavaScript's own behavior: an exception stays in `context.exception` until read.
        context.exceptionHandler = { context, exception in context?.exception = exception }
        context.evaluateScript("globalThis.console = { log() {}, error() {}, warn() {} };")
        context.evaluateScript(ModuleSource.script(from: source))
        if let exception = context.exception {
            context.exception = nil
            lastError = CompletionError(command: name, cause: exception.toString())
            return nil
        }
        guard let object = context.objectForKeyedSubscript("__smaltiSpec"), object.isObject else {
            lastError = CompletionError(command: name, cause: "the spec has no default export")
            return nil
        }
        return object
    }

    private func userFile(_ name: String) -> URL { user.appending(path: "\(name).js") }

    private func userVersion(of name: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: userFile(name).path(percentEncoded: false))
        return attributes?[.modificationDate] as? Date
    }

    /// A command name names a file in the completions folder: no paths, no hidden files.
    private static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".")
    }

    // MARK: Generators

    /// Runs a Fig generator: `custom(tokens, executeCommand, context)` when present, otherwise its `script`
    /// (argument list, shell string, or a function of the tokens returning either), whose output goes through
    /// `postProcess(output, tokens)` or is split on `splitOn` (a newline by default). Path generators answer
    /// relative to the folder being typed (`getQueryTerm`): that folder is put back in front of each name.
    private func run(_ generator: JSValue, request: GeneratorRequest) async throws(CompletionError) -> [Suggestion] {
        let items: [Suggestion]
        if Self.function(generator, "custom") != nil {
            items = try await runCustom(generator, request: request)
        } else {
            items = try await runScripted(generator, request: request)
        }
        let folder = try typedFolder(generator, request: request)
        guard !folder.isEmpty else { return items }
        return items.map {
            Suggestion(name: folder + $0.name, description: $0.description, insertValue: $0.insertValue)
        }
    }

    private func runCustom(_ generator: JSValue, request: GeneratorRequest) async throws(CompletionError)
        -> [Suggestion]
    {
        let key =
            "custom|\(request.id.spec)|\(request.id.path)|\(request.id.ordinal)|\(request.directory)|\(request.tokens)"
        if let cached = results[key], isFresh(cached.date) { return cached.value }
        guard let custom = Self.function(generator, "custom") else { return [] }
        let context = generator.context
        // Fig's generator context: its own generators (`filepaths`) read the search term and the environment.
        let fields: [String: Any] = [
            "currentWorkingDirectory": request.directory, "searchTerm": request.searchTerm, "isDangerous": false,
            "currentProcess": "zsh", "sshPrefix": "", "environmentVariables": ["HOME": NSHomeDirectory()],
        ]
        let promise = custom.call(withArguments: [
            JSValue(object: request.tokens, in: context) as Any, executor(in: request.directory, context: context),
            JSValue(object: fields, in: context) as Any,
        ])
        try Self.check(context, command: request.id.spec)
        let items = try await suggestions(settling: promise, command: request.id.spec)
        results = results.filter { isFresh($0.value.date) }
        results[key] = Cached(date: clock(), value: items)
        return items
    }

    private func runScripted(_ generator: JSValue, request: GeneratorRequest) async throws(CompletionError)
        -> [Suggestion]
    {
        let context = generator.context
        let tokenList = JSValue(object: request.tokens, in: context)
        let output = try await output(of: generator.forProperty("script"), tokens: tokenList, request: request)
        if let postProcess = Self.function(generator, "postProcess") {
            let shaped = postProcess.call(withArguments: [output, tokenList as Any])
            try Self.check(context, command: request.id.spec)
            return Self.suggestions(from: shaped)
        }
        let separator = FigSpecTranslator.text(generator.forProperty("splitOn")) ?? "\n"
        return output.components(separatedBy: separator).filter { !$0.isEmpty }.map { Suggestion(name: $0) }
    }

    /// The script's output, cached per evaluated script and directory.
    private func output(of script: JSValue?, tokens: JSValue?, request: GeneratorRequest) async throws(CompletionError)
        -> String
    {
        guard var script, !script.isUndefined, !script.isNull else { return "" }
        if Self.isFunction(script) {
            script = script.call(withArguments: [tokens as Any])
            try Self.check(script.context, command: request.id.spec)
        }
        let isShell = script.isString
        let arguments = isShell ? [script.toString() ?? ""] : FigSpecTranslator.names(of: script)
        guard !arguments.isEmpty else { return "" }
        let key = "script|\(isShell)|\(arguments)|\(request.directory)"
        if let cached = outputs[key], isFresh(cached.date) { return cached.value }
        let output =
            isShell
            ? try await runner.run(shell: arguments[0], in: request.directory).stdout
            : try await runner.run(arguments: arguments, in: request.directory).stdout
        outputs = outputs.filter { isFresh($0.value.date) }
        outputs[key] = Cached(date: clock(), value: output)
        return output
    }

    /// The part of the search term before the generator's query term (`Projects/` of `Projects/sm`).
    private func typedFolder(_ generator: JSValue, request: GeneratorRequest) throws(CompletionError) -> String {
        guard let queryTerm = Self.function(generator, "getQueryTerm") else { return "" }
        let query = queryTerm.call(withArguments: [request.searchTerm])
        try Self.check(generator.context, command: request.id.spec)
        guard let query, query.isString, let text = query.toString(), request.searchTerm.hasSuffix(text) else {
            return ""
        }
        return String(request.searchTerm.dropLast(text.count))
    }

    /// Cached outputs and results, for the tests.
    var cachedEntries: Int { outputs.count + results.count }

    private func isFresh(_ date: Date) -> Bool { clock().timeIntervalSince(date) < Self.cacheLifetime }

    /// `executeCommand({ command, args, cwd })` for custom generators: a promise of `{ stdout, stderr, status }`.
    private func executor(in directory: String, context: JSContext?) -> Any {
        let runner = runner
        let execute: @convention(block) (JSValue?) -> JSValue? = { request in
            let arguments =
                [FigSpecTranslator.text(request?.forProperty("command")) ?? ""]
                + FigSpecTranslator.names(of: request?.forProperty("args"))
            let folder = FigSpecTranslator.text(request?.forProperty("cwd")) ?? directory
            return JSValue(newPromiseIn: JSContext.current()) { resolve, reject in
                // Safe: JavaScriptCore locks its virtual machine on every call, from any thread.
                nonisolated(unsafe) let resolve = resolve
                nonisolated(unsafe) let reject = reject
                Task {
                    do {
                        let output = try await runner.run(arguments: arguments, in: folder)
                        let result: [String: Any] = ["stdout": output.stdout, "stderr": "", "status": output.status]
                        resolve?.call(withArguments: [result])
                    } catch {
                        reject?.call(withArguments: [(error as? CompletionError)?.cause ?? String(describing: error)])
                    }
                }
            }
        }
        return JSValue(object: execute, in: context) as Any
    }

    /// Waits for a promise (or takes a plain value) and reads its suggestions, for at most the runner's timeout.
    /// The wait ends once: a thenable that calls back twice, or calls back and throws, cannot resume it again.
    private func suggestions(settling value: JSValue?, command: String) async throws(CompletionError)
        -> [Suggestion]
    {
        guard let value, Self.function(value, "then") != nil else { return Self.suggestions(from: value) }
        let timeout = runner.timeout
        let outcome: Result<[Suggestion], CompletionError> = await withCheckedContinuation { continuation in
            let once = SettleOnce(continuation)
            let fulfilled: @convention(block) (JSValue?) -> Void = { result in
                once.resume(.success(Self.suggestions(from: result)))
            }
            let rejected: @convention(block) (JSValue?) -> Void = { reason in
                once.resume(.failure(CompletionError(command: command, cause: reason?.toString() ?? "rejected")))
            }
            // `invokeMethod`, not `call`: `then` needs the promise as `this`.
            value.invokeMethod(
                "then",
                withArguments: [
                    JSValue(object: fulfilled, in: value.context) as Any,
                    JSValue(object: rejected, in: value.context) as Any,
                ])
            if let exception = value.context.exception {
                value.context.exception = nil
                once.resume(.failure(CompletionError(command: command, cause: exception.toString())))
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(.failure(CompletionError(command: command, cause: "timed out after \(timeout)")))
            }
        }
        return try outcome.get()
    }

    static func suggestions(from value: JSValue?) -> [Suggestion] {
        FigSpecTranslator.elements(of: value).compactMap(FigSpecTranslator.suggestion(from:))
    }

    private static func function(_ object: JSValue, _ name: String) -> JSValue? {
        let value = object.forProperty(name)
        return value.flatMap { isFunction($0) ? $0 : nil }
    }

    private static func isFunction(_ value: JSValue) -> Bool {
        value.isObject && value.context.objectForKeyedSubscript("Function").map { value.isInstance(of: $0) } == true
    }

    private static func check(_ context: JSContext?, command: String) throws(CompletionError) {
        guard let exception = context?.exception else { return }
        context?.exception = nil
        throw CompletionError(command: command, cause: exception.toString())
    }

    private struct Manifest: Decodable {
        let commands: [String]
        let specs: [String: String]
    }

    private static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }
}

/// Specs are ES modules; JavaScriptCore evaluates scripts. The export becomes a global the loader reads.
enum ModuleSource {
    static func script(from source: String) -> String {
        if source.contains("globalThis.__smaltiSpec=") { return source }
        var text = source
        if let range = text.range(of: #"export\s*\{([^}]*)\}\s*;?\s*$"#, options: .regularExpression) {
            let inner = String(text[range]).replacingOccurrences(
                of: #"^export\s*\{|\}\s*;?\s*$"#, with: "", options: .regularExpression)
            let defaultName = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasSuffix(" as default") }?.replacingOccurrences(of: " as default", with: "")
            text.replaceSubrange(range, with: defaultName.map { "globalThis.__smaltiSpec=\($0);" } ?? "")
        }
        return text.replacingOccurrences(
            of: #"export\s+default\s+"#, with: "globalThis.__smaltiSpec = ", options: .regularExpression)
    }
}

/// What a generator runs for: the words typed, the pane's directory and which generator it is.
struct GeneratorRequest {
    let tokens: [String]
    let directory: String
    let id: GeneratorID

    var searchTerm: String { tokens.last ?? "" }
}

/// Resumes a continuation exactly once, whoever calls first (JavaScript callbacks, an exception or the deadline).
/// The flag is guarded by `lock`, so it is safe from JavaScriptCore's and the deadline's threads.
private final class SettleOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<[Suggestion], CompletionError>, Never>?

    init(_ continuation: CheckedContinuation<Result<[Suggestion], CompletionError>, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<[Suggestion], CompletionError>) {
        let pending = lock.withLock { () -> CheckedContinuation<Result<[Suggestion], CompletionError>, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: result)
    }
}
