import Foundation
import IPCAdapter
import SmaltiCore
import SmaltiIPCProtocol
import Testing

@MainActor
@Suite("Guard socket", .serialized)
struct GuardSocketTests {
    private let directory = URL(filePath: "/tmp").appending(path: "smalti-guard-\(UUID().uuidString.prefix(8))")
    private var socketFile: URL { directory.appending(path: "smalti.sock") }
    private var path: String { socketFile.path(percentEncoded: false) }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let pane = PaneID()

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func server() throws -> UnixSocketTelemetry {
        let now = self.now
        return try UnixSocketTelemetry(socketFile: socketFile, clock: { now })
    }

    private func guardLine(_ command: String, local: String = "ask") -> Data {
        let payload: [String: Any] = [
            "tool_name": "Bash", "tool_input": ["command": command], "cwd": "/p",
            "session_id": "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a", "env_database_hosts": ["db.x.com"],
            "local_verdict": local, "local_reason": "r",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let request = IPCRequest(guardFor: pane.description, hook: "PreToolUse", payload: data)
        return (try? IPCCodec.encode(request)) ?? Data()
    }

    /// Sends in the background; the task ends when the server answers.
    private func send(_ line: Data) -> Task<IPCResponse?, Never> {
        let path = self.path
        return Task.detached {
            SocketClient.send(line, to: path).flatMap { try? IPCCodec.decodeResponse($0) }
        }
    }

    @Test func guardWaitsForDecision() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var requests = telemetry.requests().makeAsyncIterator()

        let answer = send(guardLine("terraform destroy"))
        let request = try #require(await requests.next())
        try await Task.sleep(for: .milliseconds(300))
        #expect(request.use == ToolUse(tool: "Bash", command: "terraform destroy", cwd: "/p"))
        #expect(request.environmentHosts == ["db.x.com"])
        #expect(request.pane == pane)

        request.reply(.allow)

        #expect(await answer.value == IPCResponse(ok: true, error: nil, decision: .allow, reason: nil))
    }

    @Test func denialCarriesItsReason() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var requests = telemetry.requests().makeAsyncIterator()

        let answer = send(guardLine("terraform destroy"))
        try #require(await requests.next()).reply(.deny("rechazado"))

        #expect(await answer.value == IPCResponse(ok: true, error: nil, decision: .deny, reason: "rechazado"))
    }

    @Test func guardAlsoReportsPreToolUse() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var events = telemetry.events().makeAsyncIterator()
        var requests = telemetry.requests().makeAsyncIterator()

        let answer = send(guardLine("git status", local: "allow"))
        let event = await events.next()
        try #require(await requests.next()).reply(.allow)
        _ = await answer.value

        #expect(event?.hook == .preToolUse)
        #expect(event?.toolSummary == "git status")
    }

    @Test func localDenialArrivesAsDeny() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var requests = telemetry.requests().makeAsyncIterator()

        let answer = send(guardLine("cat .env", local: "deny"))
        let request = try #require(await requests.next())
        request.reply(.deny("r"))
        _ = await answer.value

        guard case .deny(let denial) = request.localVerdict else {
            Issue.record("expected deny")
            return
        }
        #expect(denial.reason == "r")
    }

    @Test func appStopDeniesOpenConnections() async throws {
        let telemetry = try server()
        var requests = telemetry.requests().makeAsyncIterator()

        let answer = send(guardLine("terraform destroy"))
        _ = await requests.next()
        telemetry.stop()

        #expect(
            await answer.value
                == IPCResponse(ok: true, error: nil, decision: .deny, reason: GuardReasons.unreachable))
    }

    @Test func truncatedFlagReachesTheRequest() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var requests = telemetry.requests().makeAsyncIterator()
        let payload: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": "echo"], "truncated": true]
        let line = try IPCCodec.encode(
            IPCRequest(
                guardFor: pane.description, hook: "PreToolUse",
                payload: try JSONSerialization.data(withJSONObject: payload)))

        let answer = send(line)
        let request = try #require(await requests.next())
        request.reply(.allow)
        _ = await answer.value

        #expect(request.isTruncated)
    }

    /// Review 1: the event a guard reports keeps F2's limits: at most 2,000 characters, and redacted.
    @Test func guardEventSummaryIsCappedAndRedacted() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var events = telemetry.events().makeAsyncIterator()
        var requests = telemetry.requests().makeAsyncIterator()

        let answer = send(guardLine("psql postgres://u:p4ss@h/db " + String(repeating: "x", count: 5_000)))
        let event = await events.next()
        try #require(await requests.next()).reply(.allow)
        _ = await answer.value

        #expect((event?.toolSummary?.count ?? 0) <= 2_000)
        #expect(event?.toolSummary?.contains("p4ss") == false)
    }

    @Test func eventRequestsStillAnswerOk() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }

        let line = try IPCCodec.encode(IPCRequest(pane: pane.description, hook: "Stop", payload: Data("{}".utf8)))

        #expect(await send(line).value == IPCResponse(ok: true, error: nil))
    }
}
