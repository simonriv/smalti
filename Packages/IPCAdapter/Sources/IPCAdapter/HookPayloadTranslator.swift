import Foundation
import SmaltiCore
import SmaltiIPCProtocol

public enum IPCError: Error, Equatable, Sendable {
    case socketInUse(path: String)
    case socketFailed(operation: String, path: String, code: Int32)
    case invalidRequest(reason: String)
}

/// Turns a Claude Code hook payload into an `AgentEvent`, at the adapter's frontier. Unknown fields are ignored, so a
/// newer Claude Code that adds fields keeps working.
public enum HookPayloadTranslator {
    public static func event(_ request: IPCRequest, at date: Date) throws(IPCError) -> AgentEvent {
        guard let uuid = UUID(uuidString: request.pane) else { throw .invalidRequest(reason: "pane \(request.pane)") }
        guard let hook = AgentHook(rawValue: request.hook) else {
            throw .invalidRequest(reason: "hook \(request.hook)")
        }
        let fields = (try? JSONSerialization.jsonObject(with: request.payload)) as? [String: Any] ?? [:]
        return AgentEvent(
            pane: PaneID(rawValue: uuid), hook: hook, at: date, sessionID: fields["session_id"] as? String,
            prompt: fields["prompt"] as? String, toolSummary: toolSummary(fields),
            message: fields["message"] as? String ?? fields["error"] as? String)
    }

    /// `pnpm db:migrate` for a shell command; `Edit /a/b.ts` for a file tool; the tool name otherwise.
    private static func toolSummary(_ fields: [String: Any]) -> String? {
        guard let tool = fields["tool_name"] as? String else { return nil }
        let input = fields["tool_input"] as? [String: Any] ?? [:]
        if tool == "Bash", let command = input["command"] as? String { return command }
        if let file = input["file_path"] as? String { return "\(tool) \(file)" }
        return tool
    }
}
