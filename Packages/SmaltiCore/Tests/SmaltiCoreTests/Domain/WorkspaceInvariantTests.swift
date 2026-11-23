import SmaltiCore
import Testing

@Suite("Workspace invariants")
struct WorkspaceInvariantTests {
    private static let seed: UInt64 = 0x5A17
    private static let stepCount = 500
    private let geometry = LayoutGeometry.standard(area: Rect(x: 10, y: 10, width: 1308, height: 732))

    private func apply(
        operation: Int, to workspace: Workspace, using generator: inout SeededGenerator
    ) throws -> Workspace {
        let ids = workspace.panes.map(\.id)
        let pick = { (generator: inout SeededGenerator) in ids.randomElement(using: &generator) }
        switch operation {
        case 0:
            let directory = try WorkingDirectory(path: "/tmp")
            return workspace.adding(Pane(id: PaneID(), workingDirectory: directory))
        case 1: return workspace.removing(pick(&generator) ?? PaneID())
        case 2: return workspace.swapping(pick(&generator) ?? PaneID(), pick(&generator) ?? PaneID())
        case 3:
            let layout = LayoutCatalog.standard.all.randomElement(using: &generator)
            return layout.map { workspace.switchingLayout(to: $0) } ?? workspace
        case 4:
            let direction = Direction.allCases.randomElement(using: &generator) ?? .right
            let request = ResizeRequest(
                pane: pick(&generator) ?? PaneID(), direction: direction,
                step: ResizeRequest.defaultStep)
            return workspace.resizing(request, within: geometry)
        case 5: return workspace.equalized()
        default: return workspace.focusing(pick(&generator) ?? PaneID())
        }
    }

    @Test func treeAndFocusStayConsistentUnderRandomOperations() throws {
        var generator = SeededGenerator(seed: Self.seed)
        var workspace = Workspace.empty(
            name: "w", rootDirectory: try WorkingDirectory(path: "/Users/s"), layout: DwindleLayout())

        for step in 1...Self.stepCount {
            let operation = Int.random(in: 0...6, using: &generator)
            workspace = try apply(operation: operation, to: workspace, using: &generator)

            let seed = String(Self.seed, radix: 16, uppercase: true)
            let context = "seed 0x\(seed), step \(step), operation \(operation)"
            let paneIDs = workspace.panes.map(\.id)
            #expect(Set(workspace.tree?.panes ?? []) == Set(paneIDs), "\(context)")
            #expect(workspace.tree?.panes ?? [] == paneIDs, "\(context)")
            #expect(workspace.tree?.panes.count ?? 0 == paneIDs.count, "\(context)")
            #expect(workspace.panes.isEmpty == (workspace.focusedPane == nil), "\(context)")
            if let focused = workspace.focusedPane {
                #expect(paneIDs.contains(focused), "\(context)")
            }
        }
    }
}
