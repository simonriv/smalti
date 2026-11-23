import Foundation

/// One command run at a Smalti pane's prompt, with where, how and when it ended.
public struct HistoryEntry: Codable, Equatable, Sendable {
    public let command: String
    public let directory: String
    public let exit: Int?
    public let duration: TimeInterval?
    public let date: Date
    public let pane: PaneID

    public init(command: String, directory: String, exit: Int?, duration: TimeInterval?, date: Date, pane: PaneID) {
        self.command = command
        self.directory = directory
        self.exit = exit
        self.duration = duration
        self.date = date
        self.pane = pane
    }

    public var hasFailed: Bool { exit.map { $0 != 0 } ?? false }
}

extension PaneID: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UUID.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
