import Foundation
import SmaltiCore
import Testing

@Suite("Project changes (F8.5)")
struct ProjectChangesTests {
    private func command(_ text: String, _ place: String? = nil) -> PlannedCommand {
        PlannedCommand(command: text, place: place)
    }

    private func approval(_ commands: [PlannedCommand], panes: Int = 3, layout: String = "dwindle")
        -> ProjectApproval
    {
        ProjectApproval(
            fingerprint: "old", approvedAt: Date(timeIntervalSince1970: 0), commands: commands, paneCount: panes,
            layout: layout)
    }

    @Test func firstTimeShowsEveryCommandUnchanged() {
        let changes = ProjectChanges(
            approved: nil, current: [command("npm run dev", "web"), command("claude --continue")], paneCount: 3,
            layout: "dwindle")

        #expect(changes.isFirstTime)
        #expect(changes.lines.map(\.kind) == [.same, .same])
        #expect(changes.arrangement == nil)
        #expect(!changes.hasSameCommands)
    }

    @Test func addedAndRemovedCommands() {
        let changes = ProjectChanges(
            approved: approval([command("npm run dev", "web"), command("nvim +42 src/a.ts")]),
            current: [command("npm run dev", "web"), command("docker compose up db")], paneCount: 3,
            layout: "dwindle")

        #expect(!changes.isFirstTime)
        #expect(changes.lines.map(\.command.command) == ["npm run dev", "docker compose up db", "nvim +42 src/a.ts"])
        #expect(changes.lines.map(\.kind) == [.same, .added, .removed])
    }

    @Test func theSameCommandInAnotherFolderIsAChange() {
        let changes = ProjectChanges(
            approved: approval([command("make", "api")]), current: [command("make", "web")], paneCount: 3,
            layout: "dwindle")

        #expect(changes.lines.map(\.kind) == [.added, .removed])
    }

    @Test func duplicatesCountAsAMultiset() {
        let changes = ProjectChanges(
            approved: approval([command("npm test")]), current: [command("npm test"), command("npm test")],
            paneCount: 3, layout: "dwindle")

        #expect(changes.lines.map(\.kind) == [.same, .added])
    }

    @Test func arrangementChangeIsReported() {
        let changes = ProjectChanges(
            approved: approval([command("ls")], panes: 3, layout: "dwindle"), current: [command("ls")], paneCount: 4,
            layout: "columns")

        #expect(
            changes.arrangement == ProjectArrangementChange(before: .init(3, "dwindle"), after: .init(4, "columns")))
    }

    @Test func onlyTheLayoutChanging() {
        let changes = ProjectChanges(
            approved: approval([command("ls")], panes: 3, layout: "dwindle"), current: [command("ls")], paneCount: 3,
            layout: "master")

        #expect(changes.arrangement != nil)
    }

    @Test func sameCommandsAndArrangement() {
        let changes = ProjectChanges(
            approved: approval([command("ls")]), current: [command("ls")], paneCount: 3, layout: "dwindle")

        #expect(changes.arrangement == nil)
        #expect(changes.hasSameCommands)
    }
}
