/// A problem found while reading the configuration. `file` is empty and `line` nil when the source is unknown.
public struct ConfigError: Error, Equatable, Sendable {
    public let file: String
    public let line: Int?
    public let key: String?
    public let problem: ConfigProblem

    public init(file: String, line: Int?, key: String?, problem: ConfigProblem) {
        self.file = file
        self.line = line
        self.key = key
        self.problem = problem
    }

    /// One line for the interface, e.g. `config.toml:12 · font_size: se esperaba un número`.
    public func summary(_ texts: ConfigTexts) -> String {
        let reason = texts.describe(problem)
        let detail = key.map { "\($0): \(reason)" } ?? reason
        return [location, detail].compactMap(\.self).joined(separator: " · ")
    }

    /// The same error under another file name (the status bar shows only the last component).
    public func located(in file: String) -> ConfigError {
        ConfigError(file: file, line: line, key: key, problem: problem)
    }

    private var location: String? {
        guard !file.isEmpty else { return nil }
        return line.map { "\(file):\($0)" } ?? file
    }
}
