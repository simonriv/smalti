import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// F7.6 (review 1, I2): a layout saved by a newer Smalti is still listed, saying so, instead of vanishing.
@MainActor
@Suite("ListNamedLayouts")
struct ListNamedLayoutsTests {
    private let layouts = InMemoryNamedLayouts()
    private let workspace = SessionArchiveContract.snapshot.workspaces[0]

    @Test func listsSavedLayoutsWithTheirCounts() throws {
        try layouts.save(workspace, as: LayoutName("solen"))

        let summaries = ListNamedLayouts(layouts: layouts).execute()

        #expect(summaries == [NamedLayoutSummary(name: try LayoutName("solen"), paneCount: 1, agentCount: 1)])
    }

    @Test func listsANewerLayoutWithItsFormat() throws {
        layouts.newer[try LayoutName("futuro")] = 2

        let summaries = ListNamedLayouts(layouts: layouts).execute()

        #expect(summaries.map(\.newerFormat) == [2])
        #expect(summaries.map(\.name.rawValue) == ["futuro"])
    }

    @Test func newerLayoutSubtitleSaysWhyItWillNotOpen() throws {
        let summary = NamedLayoutSummary(name: try LayoutName("futuro"), newerFormat: 2)
        let commands = CommandCatalog.commands(
            for: CatalogState(
                workspaces: WorkspaceSet(
                    first: Workspace.empty(
                        name: "p", rootDirectory: try WorkingDirectory(path: "/tmp/p"), layout: DwindleLayout())),
                savedLayouts: [summary]),
            keymap: .standard, layouts: .standard, texts: .spanish)

        let restore = commands.first { $0.id == .layoutRestore(summary.name) }

        #expect(restore?.subtitle == "— guardado por una versión más nueva de Smalti (formato 2)")
        // Mutation (review 1): the row is never marked as the current layout.
        #expect(restore?.isCurrent == false)
        #expect(restore?.group == .workspaces)
    }
}
