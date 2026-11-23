import Foundation

/// Which saved panes the user chose to restore, kept as the ones left out.
public struct RestoreSelection: Equatable, Sendable {
    public let unchecked: Set<UUID>

    public init(unchecked: Set<UUID>) {
        self.unchecked = unchecked
    }

    /// Shells and live agents come checked. A program to relaunch and a finished agent start unchecked: running
    /// something again unasked can have effects (a `pnpm db:migrate`), and a finished session has nothing to resume.
    public static func defaults(for snapshot: SessionSnapshot) -> RestoreSelection {
        let panes = snapshot.workspaces.flatMap(\.panes)
        let offByDefault = panes.filter { $0.relaunch != nil || $0.agent?.lastState == .stopped }
        return RestoreSelection(unchecked: Set(offByDefault.map(\.id)))
    }

    public func toggling(_ id: UUID) -> RestoreSelection {
        RestoreSelection(unchecked: unchecked.symmetricDifference([id]))
    }

    public func isChecked(_ id: UUID) -> Bool { !unchecked.contains(id) }

    public func checkedCount(in snapshot: SessionSnapshot) -> Int {
        snapshot.workspaces.flatMap(\.panes).count { isChecked($0.id) }
    }
}
