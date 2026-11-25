import Foundation
import SmaltiCore
import SmaltiIPCProtocol

/// How a guard request reaches the app and waits for its answer; the real one is the pane's Unix socket.
protocol GuardTransport: Sendable {
    func exchange(_ line: Data, to socket: String, connectTimeout: Duration, answerTimeout: Duration)
        throws(TransportError) -> Data
}

/// The tool call of a `PreToolUse` hook and the CLI's own verdict on it, without the user's settings.
struct ScreenedToolUse {
    let fields: [String: Any]
    let use: ToolUse
    let environmentHosts: [String]
    let verdict: GuardVerdict

    /// Variables whose database URL tells the environment; only their host is kept.
    static let databaseVariables = [
        "DATABASE_URL", "DIRECT_URL", "POSTGRES_URL", "POSTGRES_PRISMA_URL", "POSTGRES_URL_NON_POOLING",
        "SUPABASE_DB_URL",
    ]

    /// nil when the input is not a tool call (nothing to guard).
    init?(input: Data, environment: [String: String]) {
        guard let fields = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
            let tool = fields["tool_name"] as? String
        else { return nil }
        let toolInput = fields["tool_input"] as? [String: Any] ?? [:]
        self.fields = fields
        use = ToolUse(
            tool: tool, command: toolInput["command"] as? String,
            filePath: toolInput["file_path"] as? String ?? toolInput["notebook_path"] as? String,
            searchPath: toolInput["path"] as? String, glob: toolInput["glob"] as? String, cwd: fields["cwd"] as? String)
        environmentHosts = Self.databaseVariables.compactMap { environment[$0].flatMap(DatabaseURL.host(of:)) }
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        verdict = ScreenToolUse.verdict(
            for: use, context: GuardContext(settings: .standard, environmentHosts: environmentHosts), home: home)
    }

    var verdictName: String {
        switch verdict {
        case .allow: "allow"
        case .deny: "deny"
        case .ask: "ask"
        }
    }
}

/// The JSON a `PreToolUse` hook prints to refuse a tool call (spec F7.5); allowing prints nothing.
enum HookOutput {
    /// Used when the JSON cannot be built: still a denial (review 1).
    static let fallbackDenial =
        #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Smalti"}}"#
        + "\n"

    static func denial(_ reason: String) -> String {
        let object: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason,
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return fallbackDenial
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// `smalti guard PreToolUse` (spec F7.5): a secret read is denied at once; a destructive command waits for Smalti's
/// decision on the pane's socket; anything that goes wrong while it waits denies (fail closed).
enum GuardCommand {
    static let deadline: Duration = .seconds(630)
    static let connectTimeout: Duration = .milliseconds(500)
    /// A denial the CLI already decided is still reported, but nobody waits long for the app.
    static let reportTimeout: Duration = .seconds(1)
    /// The longest text of `tool_input` sent to the app.
    static let maxFieldBytes = ScreenToolUse.maximumInputBytes

    static func run(_ invocation: Invocation, transport: any GuardTransport, deadline: Duration) -> String {
        // Review 1: a PreToolUse input Smalti cannot read is refused, not let through.
        guard let screened = ScreenedToolUse(input: invocation.input(), environment: invocation.environment) else {
            return HookOutput.denial(GuardReasons.unreadableInput)
        }
        let answer = ask(screened, invocation.environment, transport: transport, deadline: deadline)
        return output(local: screened.verdict, app: answer)
    }

    /// The app's decision, or nil when it could not be had (no socket, no answer, an answer without a decision).
    private static func ask(
        _ screened: ScreenedToolUse, _ environment: [String: String], transport: any GuardTransport,
        deadline: Duration
    ) -> IPCDecisionAnswer? {
        guard let socket = environment["SMALTI_SOCKET"], !socket.isEmpty,
            let pane = environment["SMALTI_PANE_ID"], !pane.isEmpty,
            let line = try? IPCCodec.encode(IPCRequest(guardFor: pane, hook: "PreToolUse", payload: payload(screened)))
        else { return nil }
        let wait = screened.verdictName == "deny" ? reportTimeout : deadline
        guard
            let data = try? transport.exchange(line, to: socket, connectTimeout: connectTimeout, answerTimeout: wait),
            let end = data.firstIndex(of: UInt8(ascii: "\n")),
            let response = try? IPCCodec.decodeResponse(data.prefix(upTo: end)),
            response.ok, let decision = response.decision
        else { return nil }
        return IPCDecisionAnswer(decision: decision, reason: response.reason)
    }

    /// The stricter of both: a local denial always stands; an approval needs the app's `allow`.
    private static func output(local: GuardVerdict, app: IPCDecisionAnswer?) -> String {
        switch (local, app?.decision) {
        case (.deny(let denial), _): HookOutput.denial(denial.reason)
        case (_, .deny?): HookOutput.denial(app?.reason ?? GuardReasons.unreachable)
        case (_, .allow?): ""
        case (.allow, nil): ""
        case (.ask, nil): HookOutput.denial(GuardReasons.unreachable)
        }
    }

    private static func payload(_ screened: ScreenedToolUse) -> Data {
        var kept: [String: Any] = [
            "tool_name": screened.use.tool, "env_database_hosts": screened.environmentHosts,
            "local_verdict": screened.verdictName,
        ]
        let toolInput: [String: String?] = [
            "command": screened.use.command, "file_path": screened.use.filePath, "path": screened.use.searchPath,
            "glob": screened.use.glob,
        ]
        kept["tool_input"] = toolInput.compactMapValues { $0.map(truncated) }
        if toolInput.values.contains(where: { ($0?.utf8.count ?? 0) > maxFieldBytes }) { kept["truncated"] = true }
        kept["cwd"] = screened.use.cwd
        kept["session_id"] = screened.fields["session_id"] as? String
        if case .deny(let denial) = screened.verdict { kept["local_reason"] = denial.reason }
        return (try? JSONSerialization.data(withJSONObject: kept)) ?? Data("{}".utf8)
    }

    private static func truncated(_ text: String) -> String {
        guard text.utf8.count > maxFieldBytes else { return text }
        return String(decoding: text.utf8.prefix(maxFieldBytes), as: UTF8.self)
    }
}

struct IPCDecisionAnswer {
    let decision: IPCDecision
    let reason: String?
}
