/// What a report says about the build and the machine: "Smalti 0.4.5 (abc1234) · macOS 27.2 · Apple M4".
public struct BuildInfo: Equatable, Sendable {
    public let version: String
    public let commit: String
    public let macOS: String
    public let chip: String

    public init(version: String, commit: String, macOS: String, chip: String) {
        self.version = version
        self.commit = commit
        self.macOS = macOS
        self.chip = chip
    }

    public var summary: String { "Smalti \(version) (\(commit)) · macOS \(macOS) · \(chip)" }
}
