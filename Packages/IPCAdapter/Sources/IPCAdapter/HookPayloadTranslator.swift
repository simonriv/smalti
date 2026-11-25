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
            pane: PaneID(rawValue: uuid), hook: hook, at: date, sessionID: sessionID(fields["session_id"]),
            prompt: fields["prompt"] as? String, toolSummary: toolSummary(fields),
            message: fields["message"] as? String ?? fields["error"] as? String, source: fields["source"] as? String,
            edit: hook == .postToolUse ? edit(fields) : nil)
    }

    private static let fileTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]

    /// F6: which file a file tool wrote and the text it wrote, for "Editados por Claude".
    private static func edit(_ fields: [String: Any]) -> FileEdit? {
        guard let tool = fields["tool_name"] as? String, fileTools.contains(tool) else { return nil }
        let input = fields["tool_input"] as? [String: Any] ?? [:]
        guard let path = input["file_path"] as? String ?? input["notebook_path"] as? String else { return nil }
        let edits = input["edits"] as? [[String: Any]] ?? []
        let content = (input["content"] as? String).flatMap { $0.split(separator: "\n").first.map(String.init) }
        let text =
            input["new_string"] as? String ?? edits.first?["new_string"] as? String ?? content
            ?? input["new_source"] as? String
        return FileEdit(tool: tool, path: path, newText: text)
    }

    /// Claude Code session ids are UUIDs; anything else is dropped, because it is later typed into a shell
    /// (`claude --resume <id>`).
    private static func sessionID(_ value: Any?) -> String? {
        guard let text = value as? String, UUID(uuidString: text) != nil else { return nil }
        return text
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
