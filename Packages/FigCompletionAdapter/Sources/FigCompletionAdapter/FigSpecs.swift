import Foundation
import JavaScriptCore
import SmaltiCore

/// Completion specs in Fig's format, run with JavaScriptCore: the bundled ones (`Specs/`, vendored by
/// `scripts/fig/vendor_specs.py`) and the user's own in `~/.config/smalti/completions/*.js`, which win.
///
/// Each spec loads once into its own `JSContext` on one virtual machine; this actor serializes every use of them.
/// A generator's result is cached for `cacheLifetime` per generator and directory.
public actor FigSpecs: CompletionProvider {
    public static let cacheLifetime: TimeInterval = 30

    private struct Loaded {
        let spec: CompletionSpec
        let context: JSContext
    }

    private struct CachedResult {
        let date: Date
        let items: [Suggestion]
    }

    private let bundled: URL?
    private let bundledNames: [String: String]
    private let bundledCommands: [String]
    private let user: URL
    private let runner: GeneratorRunner
    private let clock: @Sendable () -> Date
    private let machine = JSVirtualMachine()
    private var loaded: [String: Loaded] = [:]
    private var failed: Set<String> = []
    private var generators: [GeneratorID: JSValue] = [:]
    private var cache: [String: CachedResult] = [:]
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
        if let spec = loaded[command]?.spec { return spec }
        guard !failed.contains(command), let object = module(command) else { return nil }
        // Each `loadSpec` gets a context of its own: minified modules share short global names.
        var translator = FigSpecTranslator(specName: command) { name in self.module(name) }
        let spec = translator.spec(from: object)
        generators.merge(translator.generators) { _, new in new }
        loaded[command] = Loaded(spec: spec, context: object.context)
        return spec
    }

    public func generate(_ generator: GeneratorID, tokens: [String], in directory: String) async throws(CompletionError)
        -> [Suggestion]
    {
        let key = "\(generator.spec)|\(generator.path.joined(separator: " "))|\(generator.ordinal)|\(directory)"
        if let cached = cache[key], clock().timeIntervalSince(cached.date) < Self.cacheLifetime { return cached.items }
        guard let value = generators[generator] else {
            throw CompletionError(command: generator.spec, cause: "unknown generator \(generator.ordinal)")
        }
        do {
            let items = try await run(value, tokens: tokens, in: directory, command: generator.spec)
            cache[key] = CachedResult(date: clock(), items: items)
            return items
        } catch {
            lastError = error
            throw error
        }
    }

    public func paths(matching prefix: String, in directory: String, foldersOnly: Bool) async -> [Suggestion] {
        PathListing(prefix: prefix, directory: directory).entries(foldersOnly: foldersOnly)
    }

    private var userPath: String { user.path(percentEncoded: false) }

    /// Evaluates a spec module in a fresh context and returns its default export, or nil (remembering why).
    private func module(_ name: String) -> JSValue? {
        guard let source = source(of: name), let context = JSContext(virtualMachine: machine) else {
            failed.insert(name)
            return nil
        }
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript("globalThis.console = { log() {}, error() {}, warn() {} };")
        context.evaluateScript(ModuleSource.script(from: source))
        let object = context.objectForKeyedSubscript("__smaltiSpec")
        guard exception == nil, let object, object.isObject else {
            failed.insert(name)
            lastError = CompletionError(command: name, cause: exception ?? "the spec has no default export")
            return nil
        }
        return object
    }

    // MARK: Generators

    /// Runs a Fig generator: `custom(tokens, executeCommand, context)` when present, otherwise its `script`
    /// (argument list, shell string, or a function of the tokens returning either), whose output goes through
    /// `postProcess(output, tokens)` or is split on `splitOn` (a newline by default).
    private func run(_ generator: JSValue, tokens: [String], in directory: String, command: String)
        async throws(CompletionError) -> [Suggestion]
    {
        let context = generator.context
        let tokenList = JSValue(object: tokens, in: context)
        if let custom = Self.function(generator, "custom") {
            // Fig's generator context: its own generators (`filepaths`) read the search term and the environment.
            let request = JSValue(
                object: [
                    "currentWorkingDirectory": directory, "searchTerm": tokens.last ?? "", "isDangerous": false,
                    "currentProcess": "zsh", "sshPrefix": "", "environmentVariables": ["HOME": NSHomeDirectory()],
                ] as [String: Any], in: context)
            let promise = custom.call(withArguments: [
                tokenList as Any, executor(in: directory, context: context), request as Any,
            ])
            try Self.check(context, command: command)
            return try await suggestions(settling: promise, command: command)
        }
        let output = try await runScript(generator.forProperty("script"), tokens: tokenList, in: directory)
        if let postProcess = Self.function(generator, "postProcess") {
            let shaped = postProcess.call(withArguments: [output, tokenList as Any])
            try Self.check(context, command: command)
            return Self.suggestions(from: shaped)
        }
        let separator = FigSpecTranslator.text(generator.forProperty("splitOn")) ?? "\n"
        return output.components(separatedBy: separator).filter { !$0.isEmpty }.map { Suggestion(name: $0) }
    }

    private func runScript(_ script: JSValue?, tokens: JSValue?, in directory: String) async throws(CompletionError)
        -> String
    {
        guard var script, !script.isUndefined, !script.isNull else { return "" }
        if Self.isFunction(script) { script = script.call(withArguments: [tokens as Any]) }
        if script.isString { return try await runner.run(shell: script.toString(), in: directory).stdout }
        let arguments = FigSpecTranslator.names(of: script)
        guard !arguments.isEmpty else { return "" }
        return try await runner.run(arguments: arguments, in: directory).stdout
    }

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

    /// Waits for a promise (or takes a plain value) and reads its suggestions.
    private func suggestions(settling value: JSValue?, command: String) async throws(CompletionError)
        -> [Suggestion]
    {
        guard let value, Self.function(value, "then") != nil else { return Self.suggestions(from: value) }
        let outcome: Result<[Suggestion], CompletionError> = await withCheckedContinuation { continuation in
            let fulfilled: @convention(block) (JSValue?) -> Void = { result in
                continuation.resume(returning: .success(Self.suggestions(from: result)))
            }
            let rejected: @convention(block) (JSValue?) -> Void = { reason in
                continuation.resume(
                    returning: .failure(CompletionError(command: command, cause: reason?.toString() ?? "rejected")))
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
                continuation.resume(returning: .failure(CompletionError(command: command, cause: exception.toString())))
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

    private func source(of name: String) -> String? {
        let own = user.appending(path: "\(name).js")
        if let text = try? String(contentsOf: own, encoding: .utf8) { return text }
        guard let bundled, let file = bundledNames[name] else { return nil }
        return try? String(contentsOf: bundled.appending(path: file), encoding: .utf8)
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
