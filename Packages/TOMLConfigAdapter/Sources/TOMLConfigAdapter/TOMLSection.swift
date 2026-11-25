import SmaltiCore
import TOMLDecoder

/// The raw text of a configuration file and the name errors should show for it.
struct TOMLSource {
    let text: String
    let file: String
}

/// F7.6: where a file written for a newer Smalti collects the dotted names of the keys this build does not know.
final class IgnoredKeys {
    private(set) var names: [String] = []

    func append(_ name: String) { names.append(name) }
}

/// One TOML table read as configuration: typed accessors whose failures are `ConfigError`s that name the key and,
/// through `TOMLKeyLocator`, its line. This is the frontier where `TOMLError` is translated.
struct TOMLSection {
    private static let syntaxReason = "sintaxis TOML no válida"
    private static let tableReason = "se esperaba una tabla"
    private static let numberReason = "se esperaba un número"
    private static let textReason = "se esperaba un texto"
    private static let flagReason = "se esperaba true o false"

    /// Dotted path of the table, `""` for the top level.
    let name: String
    private let table: TOMLTable
    private let source: TOMLSource
    /// Set when reading a newer file: unknown keys are collected here instead of failing.
    private let ignored: IgnoredKeys?

    private init(name: String, table: TOMLTable, source: TOMLSource, ignored: IgnoredKeys? = nil) {
        self.name = name
        self.table = table
        self.source = source
        self.ignored = ignored
    }

    /// F7.6 (review 1): in a newer file, a value this build does not know (a command, a module, a choice) is skipped
    /// and named, so the rest of the file still applies; in a current file it is the error `error` describes.
    func skipUnknownValue(_ value: String, at key: String, else error: ConfigError) throws(ConfigError) {
        guard let ignored else { throw error }
        ignored.append("\(dotted(key)) = \(value)")
    }

    /// The same table, and every table read from it, collecting unknown keys into `ignored` instead of failing.
    func collectingUnknownKeys(into ignored: IgnoredKeys) -> TOMLSection {
        TOMLSection(name: name, table: table, source: source, ignored: ignored)
    }

    /// The top-level table, or a syntax error with the line the library reports.
    static func root(of source: TOMLSource) throws(ConfigError) -> TOMLSection {
        do {
            return TOMLSection(name: "", table: try TOMLTable(source: source.text), source: source)
        } catch {
            throw ConfigError(file: source.file, line: lineNumber(in: error), key: nil, reason: syntaxReason)
        }
    }

    /// Keys in the order they are written; keys the locator cannot place go last.
    var keysInFileOrder: [String] {
        table.keys.sorted { (line(of: $0) ?? .max) < (line(of: $1) ?? .max) }
    }

    func error(at key: String, _ reason: String) -> ConfigError {
        ConfigError(file: source.file, line: line(of: key), key: key, reason: reason)
    }

    /// Fails on the first key, in file order, that is not in `allowed`.
    func rejectUnknownKeys(allowed: Set<String>) throws(ConfigError) {
        if let ignored {
            keysInFileOrder.filter { !allowed.contains($0) }.forEach { ignored.append(dotted($0)) }
            return
        }
        guard let unknown = keysInFileOrder.first(where: { !allowed.contains($0) }) else { return }
        throw error(at: unknown, isTable(unknown) ? "tabla desconocida" : "clave desconocida")
    }

    /// The nested table at `key`, or `nil` when it is not written.
    func section(_ key: String) throws(ConfigError) -> TOMLSection? {
        try value(
            at: key, read: { (table) throws(TOMLError) in try table.table(forKey: key) },
            reason: { _ in Self.tableReason }
        )
        .map { TOMLSection(name: dotted(key), table: $0, source: source, ignored: ignored) }
    }

    /// An integer or float at `key`, or `nil` when it is not written. `nan` and `inf` come back as written.
    func number(_ key: String) throws(ConfigError) -> Double? {
        try value(
            at: key, read: { (table) throws(TOMLError) in try table.float(forKey: key) },
            reason: { _ in Self.numberReason })
    }

    /// A boolean at `key`, or `nil` when it is not written.
    func flag(_ key: String) throws(ConfigError) -> Bool? {
        try value(
            at: key, read: { (table) throws(TOMLError) in try table.bool(forKey: key) },
            reason: { _ in Self.flagReason })
    }

    /// A string at `key`, or `nil` when it is not written. `reason` explains a value of another type; a string
    /// the library cannot decode (an invalid escape, which it only reports on read) is a syntax error.
    func text(_ key: String, reason: String = textReason) throws(ConfigError) -> String? {
        try value(at: key, read: { (table) throws(TOMLError) in try table.string(forKey: key) }) { error in
            Self.isTypeMismatch(error) ? reason : Self.syntaxReason
        }
    }

    /// An array of strings at `key`, or `nil` when it is not written.
    func texts(_ key: String, reason: String = "se esperaba una lista de textos") throws(ConfigError) -> [String]? {
        try value(
            at: key,
            read: { (table) throws(TOMLError) in
                let array = try table.array(forKey: key)
                var texts: [String] = []
                for index in 0..<array.count { texts.append(try array.string(atIndex: index)) }
                return texts
            },
            reason: { _ in reason })
    }

    /// Reads `key` with `read`, or `nil` when it is not written; a failure becomes a `ConfigError` at `key`.
    private func value<Value>(
        at key: String, read: (TOMLTable) throws(TOMLError) -> Value, reason: (TOMLError) -> String
    ) throws(ConfigError) -> Value? {
        guard table.contains(key: key) else { return nil }
        do {
            return try read(table)
        } catch {
            throw self.error(at: key, reason(error))
        }
    }

    private func dotted(_ key: String) -> String { name.isEmpty ? key : "\(name).\(key)" }

    private func line(of key: String) -> Int? {
        TOMLKeyLocator.line(of: key, inTable: name, text: source.text)
    }

    private func isTable(_ key: String) -> Bool {
        do {
            _ = try table.table(forKey: key)
            return true
        } catch {
            return false
        }
    }

    /// TOMLDecoder keeps the failure kind in a non-public field; its description names a type mismatch.
    private static func isTypeMismatch(_ error: TOMLError) -> Bool {
        String(describing: error).contains("Type mismatch")
    }

    /// TOMLDecoder keeps the line in a non-public field; its description starts with `(Line N)`.
    private static func lineNumber(in error: TOMLError) -> Int? {
        String(describing: error).firstMatch(of: /^\(Line (\d+)\)/).flatMap { Int($0.1) }
    }
}
