import Foundation
import SmaltiCore
import Testing

/// Every `CommandHistory` returns what was appended, in order, across a fresh load.
public enum CommandHistoryContract {
    public static func verify(_ make: () async -> any CommandHistory) async {
        await loadEmptyIsEmpty(await make())
        await appendThenLoadReturnsEntries(await make())
    }

    private static func loadEmptyIsEmpty(_ history: any CommandHistory) async {
        #expect((try? await history.load()) == [], "a new history loads empty")
    }

    private static func appendThenLoadReturnsEntries(_ history: any CommandHistory) async {
        let pane = PaneID()
        let entries = ["git status", "swift test"].enumerated().map { offset, command in
            HistoryEntry(
                command: command, directory: "/repo", exit: offset, duration: 1.5,
                date: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset)), pane: pane)
        }
        for entry in entries { try? await history.append(entry) }
        #expect((try? await history.load()) == entries, "appended entries load back unchanged, in order")
    }
}

/// Every `ProjectContext` answers a directory that does not exist with an empty snapshot.
public enum ProjectContextContract {
    public static func verify(_ make: (_ missingDirectory: String) async -> any ProjectContext) async {
        let missing = "/nonexistent-\(UUID())"
        let context = await make(missing)
        #expect(await context.snapshot(of: missing) == .empty, "a missing directory has no project")
    }
}
