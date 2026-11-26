import Foundation

/// What the user approved of a project's file: its fingerprint and, to show what changed later, its commands and
/// arrangement as the confirmation showed them.
public struct ProjectApproval: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let approvedAt: Date
    public let commands: [PlannedCommand]
    public let paneCount: Int
    public let layout: String

    public init(fingerprint: String, approvedAt: Date, commands: [PlannedCommand], paneCount: Int, layout: String) {
        self.fingerprint = fingerprint
        self.approvedAt = approvedAt
        self.commands = commands
        self.paneCount = paneCount
        self.layout = layout
    }
}

/// A project Smalti remembers: its repo (real path), its name, when it was last opened and what was approved.
public struct ProjectRecord: Codable, Equatable, Sendable {
    public let root: String
    public let name: String
    public let lastOpened: Date
    public let approval: ProjectApproval?

    public init(root: String, name: String, lastOpened: Date, approval: ProjectApproval?) {
        self.root = root
        self.name = name
        self.lastOpened = lastOpened
        self.approval = approval
    }
}
