import Foundation
import SmaltiCore
import Testing

@Suite("Agent transitions")
struct AgentTransitionTests {
    private let pane = PaneID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ hook: AgentHook, at seconds: TimeInterval = 0, session: String? = "s1", prompt: String? = nil,
        tool: String? = nil, message: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            pane: pane, hook: hook, at: t0.addingTimeInterval(seconds), sessionID: session, prompt: prompt,
            toolSummary: tool, message: message)
    }

    private func started() -> AgentSession {
        AgentSession.start(from: event(.sessionStart))
            ?? AgentSession(
                harness: .claude, sessionID: "missing", title: nil, state: .stopped, startedAt: t0)
    }

    @Test func sessionStartWaitsForThePromptWithoutAttention() {
        let session = AgentSession.start(from: event(.sessionStart))

        #expect(session?.sessionID == "s1")
        #expect(session?.state == .waiting(since: t0, reason: .turnFinished))
        #expect(session?.startedAt == t0)
    }

    @Test func eventWithoutSessionCreatesNoAgent() {
        #expect(AgentSession.start(from: event(.sessionStart, session: nil)) == nil)
        #expect(AgentSession.start(from: event(.sessionStart, session: "")) == nil)
    }

    @Test func userPromptSubmitStartsWorkingAndTitlesTheSession() {
        let transition = started().applying(event(.userPromptSubmit, at: 5, prompt: "Agendar recordatorios"))

        #expect(transition.session.state == .working)
        #expect(transition.session.title == "Agendar recordatorios")
        #expect(transition.attention == nil)
    }

    @Test func titleIsFirstLineTruncatedTo80() {
        let long = String(repeating: "a", count: 100) + "\nsegunda línea"

        let title = started().applying(event(.userPromptSubmit, prompt: long)).session.title

        #expect(title == String(repeating: "a", count: 80))
    }

    @Test func titleIsKeptAfterFirstPrompt() {
        let first = started().applying(event(.userPromptSubmit, prompt: "primero")).session

        #expect(first.applying(event(.userPromptSubmit, prompt: "segundo")).session.title == "primero")
    }

    @Test func postToolUseKeepsWorking() {
        let waiting = started().applying(event(.permissionRequest, tool: "pnpm db:migrate")).session

        #expect(waiting.applying(event(.postToolUse, at: 9)).session.state == .working)
    }

    @Test func permissionRequestWaitsAndAsksForAttention() {
        let transition = started().applying(event(.permissionRequest, at: 3, tool: "pnpm db:migrate"))

        #expect(
            transition.session.state
                == .waiting(since: t0.addingTimeInterval(3), reason: .permission("pnpm db:migrate")))
        #expect(transition.attention == .permission("pnpm db:migrate"))
    }

    @Test func notificationWaitsWithItsMessage() {
        let working = started().applying(event(.userPromptSubmit, prompt: "x")).session

        let transition = working.applying(event(.notification, at: 4, message: "Claude is waiting for your input"))

        #expect(
            transition.session.state
                == .waiting(since: t0.addingTimeInterval(4), reason: .attention("Claude is waiting for your input")))
        #expect(transition.attention == .attention("Claude is waiting for your input"))
    }

    @Test func notificationAfterStopDoesNotRenotifyOrMoveSince() {
        let stopped = started().applying(event(.userPromptSubmit, prompt: "x")).session
            .applying(event(.stop, at: 10)).session

        let transition = stopped.applying(event(.notification, at: 70, message: "idle"))

        #expect(transition.session.state == .waiting(since: t0.addingTimeInterval(10), reason: .turnFinished))
        #expect(transition.attention == nil)
    }

    @Test func permissionThenNotificationCountsOnce() {
        let asking = started().applying(event(.permissionRequest, at: 2, tool: "rm x")).session

        let transition = asking.applying(event(.notification, at: 2, message: "Claude needs your permission"))

        #expect(transition.attention == nil)
        #expect(transition.session.state == .waiting(since: t0.addingTimeInterval(2), reason: .permission("rm x")))
    }

    @Test func stopWaitsAndAsksForAttention() {
        let working = started().applying(event(.userPromptSubmit, prompt: "x")).session

        let transition = working.applying(event(.stop, at: 30))

        #expect(transition.session.state == .waiting(since: t0.addingTimeInterval(30), reason: .turnFinished))
        #expect(transition.attention == .turnFinished)
    }

    @Test func stopFailureFailsWithItsMessage() {
        let transition = started().applying(event(.stopFailure, at: 8, message: "API error 529"))

        #expect(transition.session.state == .failed(since: t0.addingTimeInterval(8), message: "API error 529"))
        #expect(transition.attention == .failure("API error 529"))
    }

    @Test func notificationKeepsAFailedAgentFailed() {
        let failed = started().applying(event(.stopFailure, at: 8, message: "API error 529")).session

        let transition = failed.applying(event(.notification, at: 68, message: "Claude is waiting for your input"))

        #expect(transition.session.state == .failed(since: t0.addingTimeInterval(8), message: "API error 529"))
        #expect(transition.attention == nil)
    }

    @Test func preToolUseAfterAnApprovedPermissionIsWorkingAgain() {
        let asking = started().applying(event(.permissionRequest, at: 3, tool: "pnpm test")).session

        let transition = asking.applying(event(.preToolUse, at: 5))

        #expect(transition.session.state == .working)
        #expect(transition.attention == nil)
    }

    @Test func compactionSessionStartKeepsTheCurrentState() {
        let base = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
        let working = base.applying(event(.userPromptSubmit, prompt: "x")).0
        let compact = AgentEvent(
            pane: pane, hook: .sessionStart, at: t0.addingTimeInterval(9), sessionID: "s1", source: "compact")

        #expect(working.applying(compact).0.agent?.state == .working)
    }

    @Test func sessionEndStops() {
        let transition = started().applying(event(.sessionEnd, at: 50))

        #expect(transition.session.state == .stopped)
        #expect(transition.attention == nil)
    }

    @Test func paneStartsAnAgentFromAnyEventWithASession() {
        let base = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))

        let (updated, attention) = base.applying(event(.permissionRequest, tool: "ls"))

        #expect(updated.agent?.state == .waiting(since: t0, reason: .permission("ls")))
        #expect(attention == .permission("ls"))
    }

    @Test func paneIgnoresEventsWithoutASession() {
        let base = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))

        #expect(base.applying(event(.stop, session: nil)).0.agent == nil)
    }

    @Test func newSessionStartReplacesTheAgentButKeepsTheTitleOfTheSameSession() {
        let base = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
        let titled = base.applying(event(.userPromptSubmit, prompt: "tarea")).0

        let resumed = titled.applying(event(.sessionStart, at: 100)).0

        #expect(resumed.agent?.title == "tarea")
        #expect(resumed.agent?.state == .waiting(since: t0.addingTimeInterval(100), reason: .turnFinished))
    }

    @Test func claudeNonZeroExitFailsAgent() {
        let running = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
            .applying(event(.userPromptSubmit, prompt: "x")).0

        let ended = running.applying(
            .commandFinished(exitCode: 1, duration: .seconds(3)), at: t0.addingTimeInterval(60))

        #expect(ended.agent?.state == .failed(since: t0.addingTimeInterval(60), message: "salió con código 1"))
    }

    @Test func claudeCleanExitStopsAgent() {
        let running = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
            .applying(event(.userPromptSubmit, prompt: "x")).0

        #expect(running.applying(.commandFinished(exitCode: 0, duration: .seconds(3)), at: t0).agent?.state == .stopped)
    }

    @Test func leavingClaudeForTheShellStopsAgent() {
        let running = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "claude")))
            .applying(event(.userPromptSubmit, prompt: "x")).0

        let back = running.applying(.foregroundProcessChanged(ForegroundProcess(name: "zsh")), at: t0)

        #expect(back.agent?.state == .stopped)
    }

    @Test func aFailedAgentStaysFailedWhenTheShellReturns() {
        let failed = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
            .applying(event(.stopFailure, message: "boom")).0

        let back = failed.applying(.foregroundProcessChanged(ForegroundProcess(name: "zsh")), at: t0)

        #expect(back.agent?.state == .failed(since: t0, message: "boom"))
    }

    @Test func otherProgramsDoNotStopTheAgent() {
        let running = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp"))
            .applying(event(.userPromptSubmit, prompt: "x")).0

        #expect(
            running.applying(.foregroundProcessChanged(ForegroundProcess(name: "node")), at: t0).agent?.state
                == .working)
    }

    @Test func aRestoredAgentIsNotStoppedByTheShellStartingBeforeClaude() {
        let restored = Pane(id: pane, workingDirectory: SessionFixtures.directory("/tmp")).attaching(
            AgentSession(
                harness: .claude, sessionID: "s1", title: nil, state: .waiting(since: t0, reason: .turnFinished),
                startedAt: t0))

        let shellUp = restored.applying(.foregroundProcessChanged(ForegroundProcess(name: "zsh")), at: t0)

        #expect(shellUp.agent?.state == .waiting(since: t0, reason: .turnFinished))
    }
}
