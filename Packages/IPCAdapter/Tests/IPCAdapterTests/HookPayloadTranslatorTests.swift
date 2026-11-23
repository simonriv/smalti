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
            #"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"pnpm db:migrate --name add_user_prefs"}}"#)

        #expect(event.toolSummary == "pnpm db:migrate --name add_user_prefs")
        #expect(event.hook == .permissionRequest)
    }

    @Test func editPermissionSummarizesFile() throws {
        let event = try translate(
            "PermissionRequest", #"{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"/a/b.ts"}}"#)

        #expect(event.toolSummary == "Edit /a/b.ts")
    }

    @Test func toolWithoutInputIsItsName() throws {
        #expect(try translate("PermissionRequest", #"{"tool_name":"WebFetch"}"#).toolSummary == "WebFetch")
    }

    @Test func promptAndMessageAreKept() throws {
        #expect(try translate("UserPromptSubmit", #"{"session_id":"s1","prompt":"hola"}"#).prompt == "hola")
        #expect(try translate("Notification", #"{"message":"Claude needs you"}"#).message == "Claude needs you")
    }

    @Test func stopFailureUsesTheErrorWhenThereIsNoMessage() throws {
        #expect(try translate("StopFailure", #"{"error":"API error 529"}"#).message == "API error 529")
    }

    @Test func sessionStartSourceIsKept() throws {
        #expect(try translate("SessionStart", #"{"session_id":"s1","source":"compact"}"#).source == "compact")
    }

    @Test func unknownFieldsAreIgnored() throws {
        let event = try translate("Stop", #"{"session_id":"s1","nuevo_campo":{"x":1},"transcript_path":"/t"}"#)

        #expect(event == AgentEvent(pane: pane, hook: .stop, at: now, sessionID: "s1"))
    }

    @Test func invalidPaneOrHookThrows() {
        #expect(throws: IPCError.self) {
            try HookPayloadTranslator.event(IPCRequest(pane: "x", hook: "Stop", payload: Data()), at: now)
        }
        #expect(throws: IPCError.self) { try translate("Nope", "{}") }
    }
}
