import Foundation
import IPCAdapter
import SmaltiCore
import SmaltiIPCProtocol
import Testing

@Suite("Hook payload translator")
struct HookPayloadTranslatorTests {
    private let pane = PaneID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func translate(_ hook: String, _ payload: String) throws -> AgentEvent {
        try HookPayloadTranslator.event(
            IPCRequest(pane: pane.description, hook: hook, payload: Data(payload.utf8)), at: now)
    }

    @Test func bashPermissionSummarizesCommand() throws {
        let event = try translate(
            "PermissionRequest",
            #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","tool_name":"Bash","tool_input":{"command":"pnpm db:migrate --name add_user_prefs"}}"#
        )

        #expect(event.toolSummary == "pnpm db:migrate --name add_user_prefs")
        #expect(event.hook == .permissionRequest)
    }

    @Test func editPermissionSummarizesFile() throws {
        let event = try translate(
            "PermissionRequest",
            #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","tool_name":"Edit","tool_input":{"file_path":"/a/b.ts"}}"#
        )

        #expect(event.toolSummary == "Edit /a/b.ts")
    }

    @Test func toolWithoutInputIsItsName() throws {
        #expect(try translate("PermissionRequest", #"{"tool_name":"WebFetch"}"#).toolSummary == "WebFetch")
    }

    @Test func promptAndMessageAreKept() throws {
        #expect(
            try translate("UserPromptSubmit", #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","prompt":"hola"}"#)
                .prompt == "hola")
        #expect(try translate("Notification", #"{"message":"Claude needs you"}"#).message == "Claude needs you")
    }

    @Test func stopFailureUsesTheErrorWhenThereIsNoMessage() throws {
        #expect(try translate("StopFailure", #"{"error":"API error 529"}"#).message == "API error 529")
    }

    @Test func sessionStartSourceIsKept() throws {
        #expect(
            try translate("SessionStart", #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","source":"compact"}"#)
                .source == "compact")
    }

    /// Payloads captured from Claude Code 2.1.330 (`claude -p` with a hook that dumps stdin), paths anonymised.
    @Test func realPreToolUsePayloadIsTranslated() throws {
        let event = try translate(
            "PreToolUse",
            #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","prompt_id":"1014bf7a-d43a-432b-a128-0ddd43ed5ea6","permission_mode":"auto","effort":{"level":"medium"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls","description":"List files in current directory"},"tool_use_id":"toolu_01HtigXH1CxuwxxkTuyEZ1dv"}"#
        )

        #expect(event.hook == .preToolUse)
        #expect(event.sessionID == "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a")
        #expect(event.toolSummary == "ls")
    }

    @Test func realStopPayloadIsTranslated() throws {
        let event = try translate(
            "Stop",
            #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","transcript_path":"/tmp/t.jsonl","cwd":"/tmp","prompt_id":"1014bf7a-d43a-432b-a128-0ddd43ed5ea6","permission_mode":"auto","effort":{"level":"medium"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Listo.","background_tasks":[],"session_crons":[]}"#
        )

        #expect(
            event == AgentEvent(pane: pane, hook: .stop, at: now, sessionID: "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"))
    }

    @Test func unknownFieldsAreIgnored() throws {
        let event = try translate(
            "Stop",
            #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a","nuevo_campo":{"x":1},"transcript_path":"/t"}"#)

        #expect(
            event == AgentEvent(pane: pane, hook: .stop, at: now, sessionID: "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"))
    }

    @Test func invalidPaneOrHookThrows() {
        #expect(throws: IPCError.self) {
            try HookPayloadTranslator.event(IPCRequest(pane: "x", hook: "Stop", payload: Data()), at: now)
        }
        #expect(throws: IPCError.self) { try translate("Nope", "{}") }
    }

    @Test func aSessionIDThatIsNotAUUIDIsDropped() throws {
        #expect(try translate("Stop", "{\"session_id\":\"abc\\u0015rm\"}").sessionID == nil)
    }
}
