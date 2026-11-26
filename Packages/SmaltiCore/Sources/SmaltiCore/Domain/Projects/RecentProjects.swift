import Foundation

/// The projects Smalti remembers, newest first, at most `maximumCount` (F8.5).
public struct RecentProjects: Equatable, Sendable {
    public static let maximumCount = 20

    public let ordered: [ProjectRecord]

    public init(records: [ProjectRecord]) {
        ordered = records.sorted { $0.lastOpened > $1.lastOpened }
    }

    public func record(at root: String) -> ProjectRecord? {
        ordered.first { $0.root == root }
    }

    /// `root` opened now: first in the list, with its name; `approval` replaces the remembered one unless `nil`.
    public func opening(root: String, name: String, at date: Date, approval: ProjectApproval?) -> RecentProjects {
        let kept = approval ?? record(at: root)?.approval
        let opened = ProjectRecord(root: root, name: name, lastOpened: date, approval: kept)
        let others = ordered.filter { $0.root != root }.prefix(Self.maximumCount - 1)
        return RecentProjects(records: [opened] + others)
    }

    /// Without the projects whose file no longer `exists`, and how many left.
    public func pruned(keeping exists: (String) -> Bool) -> (RecentProjects, removed: Int) {
        let kept = ordered.filter { exists($0.root) }
        return (RecentProjects(records: kept), ordered.count - kept.count)
    }
}
