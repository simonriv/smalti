import SmaltiCore
import TOMLDecoder

/// The raw text of a configuration file and the name errors should show for it.
struct TOMLSource {
    let text: String
    let file: String
}

/// One TOML table read as configuration: typed accessors whose failures are `ConfigError`s that name the key and,
/// through `TOMLKeyLocator`, its line. This is the frontier where `TOMLError` is translated.
struct TOMLSection {
    private static let syntaxReason = "sintaxis TOML no válida"
    private static let tableReason = "se esperaba una tabla"
    private static let numberReason = "se esperaba un número"
    private static let textReason = "se esperaba un texto"

    /// Dotted path of the table, `""` for the top level.
    let name: String
    private let table: TOMLTable
    private let source: TOMLSource

    private init(name: String, table: TOMLTable, source: TOMLSource) {
        self.name = name
        self.table = table
        self.source = source
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
        guard let unknown = keysInFileOrder.first(where: { !allowed.contains($0) }) else { return }
        throw error(at: unknown, isTable(unknown) ? "tabla desconocida" : "clave desconocida")
    }

    /// The nested table at `key`, or `nil` when it is not written.
    func section(_ key: String) throws(ConfigError) -> TOMLSection? {
        guard table.contains(key: key) else { return nil }
        do {
            let nested = try table.table(forKey: key)
            return TOMLSection(name: name.isEmpty ? key : "\(name).\(key)", table: nested, source: source)
        } catch {
            throw self.error(at: key, Self.tableReason)
        }
    }

    /// An integer or float at `key`, or `nil` when it is not written.
    func number(_ key: String) throws(ConfigError) -> Double? {
        guard table.contains(key: key) else { return nil }
        do {
            return try table.float(forKey: key)
        } catch {
            throw self.error(at: key, Self.numberReason)
        }
    }

    /// A string at `key`, or `nil` when it is not written. `reason` explains a value of another type.
    func text(_ key: String, reason: String = textReason) throws(ConfigError) -> String? {
        guard table.contains(key: key) else { return nil }
        do {
            return try table.string(forKey: key)
        } catch {
            throw self.error(at: key, reason)
        }
    }

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

    /// TOMLDecoder keeps the line in a non-public field; its description starts with `(Line N)`.
    private static func lineNumber(in error: TOMLError) -> Int? {
        String(describing: error).firstMatch(of: /^\(Line (\d+)\)/).flatMap { Int($0.1) }
    }
}
