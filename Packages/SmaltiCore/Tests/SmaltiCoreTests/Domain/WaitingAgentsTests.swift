import Foundation
import SmaltiCore
import Testing

/// Spec F5, "Agentes que esperan": the agents of the other panes of the workspace that wait or failed.
@Suite("Workspace waiting agents")
struct WaitingAgentsTests {
    private func pane(_ hook: AgentHook?) throws -> Pane {
        let base = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/Users/simon/dev"))
        guard let hook else { return base }
        let started = base.applying(
            AgentEvent(
                pane: base.id, hook: .sessionStart, at: Date(timeIntervalSince1970: 0), sessionID: "s",
                prompt: nil, message: nil)
        ).0
        return started.applying(
            AgentEvent(
                pane: base.id, hook: hook, at: Date(timeIntervalSince1970: 1), sessionID: "s", prompt: "x",
                message: "m")
        ).0
    }

    private func workspace(_ panes: [Pane]) throws -> Workspace {
        let root = try WorkingDirectory(path: "/Users/simon/dev")
        return panes.reduce(Workspace.empty(name: "solen", rootDirectory: root, layout: DwindleLayout())) {
            $0.adding($1)
        }
    }

    @Test func anotherPaneWaitingIsListed() throws {
        let shell = try pane(nil)
        let agent = try pane(.notification)

        let waiting = try workspace([shell, agent]).waitingAgents(besides: shell.id)

        #expect(waiting == WaitingAgents(waiting: ["claude"]))
    }

    @Test func thePaneItselfIsNotListed() throws {
        let agent = try pane(.notification)

        #expect(try workspace([agent]).waitingAgents(besides: agent.id) == WaitingAgents())
    }

    @Test func workingAgentsAreNotListed() throws {
        let shell = try pane(nil)
        let agent = try pane(.userPromptSubmit)

        #expect(try workspace([shell, agent]).waitingAgents(besides: shell.id) == WaitingAgents())
    }
}
