/// A problem found while reading the configuration. `file` is empty and `line` nil when the source is unknown.
public struct ConfigError: Error, Equatable, Sendable {
    public let file: String
    public let line: Int?
    public let key: String?
    public let reason: String

    public init(file: String, line: Int?, key: String?, reason: String) {
        self.file = file
        self.line = line
        self.key = key
        self.reason = reason
    }

    /// One line for the interface, e.g. `config.toml:12 · font_size: se esperaba un número`.
    public var summary: String {
        let detail = key.map { "\($0): \(reason)" } ?? reason
        return [location, detail].compactMap(\.self).joined(separator: " · ")
    }

    private var location: String? {
        guard !file.isEmpty else { return nil }
        return line.map { "\(file):\($0)" } ?? file
    }
}
