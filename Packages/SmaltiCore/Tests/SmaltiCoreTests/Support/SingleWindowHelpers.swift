import Foundation

@testable import SmaltiCore

/// Tests written before F4.5 save and list one window's workspaces; the app always works on a `WindowSet`.
extension WindowSet {
    /// One window holding `set`, without a frame.
    static func single(_ set: WorkspaceSet) -> WindowSet {
        WindowSet(first: WindowState(id: WindowID(), workspaces: set, frame: nil, isFullScreen: false))
    }
}

extension SaveSession {
    func saveStructure(of set: WorkspaceSet, at date: Date) -> SaveOutcome {
        saveStructure(of: .single(set), at: date)
    }

    func saveWithScrollback(of set: WorkspaceSet, at date: Date) -> SaveOutcome {
        saveWithScrollback(of: .single(set), at: date)
    }
}

extension SessionSnapshot {
    static func capture(_ set: WorkspaceSet, scrollbackLines: [PaneID: Int], at date: Date) -> SessionSnapshot {
        capture(.single(set), scrollbackLines: scrollbackLines, at: date)
    }
}

extension ResumeListing {
    static func workspaces(in snapshot: SessionSnapshot, home: WorkingDirectory, harnesses: HarnessRegistry)
        -> [ResumeWorkspace]
    {
        windows(in: snapshot, home: home, harnesses: harnesses).flatMap(\.workspaces)
    }
}
