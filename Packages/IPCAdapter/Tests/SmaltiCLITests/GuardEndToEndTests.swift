import Foundation
import IPCAdapter
import SmaltiCore
import Synchronization
import Testing

@testable import smalti

/// C1 and C3 through a real socket: the CLI as the hook runs it, against Smalti's real server.
@MainActor
@Suite("Guard end to end", .serialized)
struct GuardEndToEndTests {
    private let directory = URL(filePath: "/tmp").appending(path: "smalti-e2e-\(UUID().uuidString.prefix(8))")
    private var socket: String { directory.appending(path: "smalti.sock").path(percentEncoded: false) }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static let incidents = [
        GuardCommandTests.bash("npm run db:push"), GuardCommandTests.bash("terraform destroy -auto-approve"),
        GuardCommandTests.bash(
            #"curl -X POST https://backboard.railway.app/graphql/v2 -H "Authorization: Bearer $RAILWAY_TOKEN" -H "Content-Type: application/json" -d '{"query":"mutation { volumeDelete(volumeId: \"vol_1\") }"}'"#
        ),
    ]

    /// Runs the CLI on a background thread; `output` is nil until it returns.
    private final class Run: Sendable {
        let output = Mutex<String?>(nil)
    }

    private func start(_ input: String, environment: [String: String]? = nil, deadline: Duration = .seconds(630)) -> Run
    {
        let run = Run()
        var environment = environment ?? ["SMALTI_SOCKET": socket, "SMALTI_PANE_ID": PaneID().description]
        environment["HOME"] = "/Users/u"
        let invocation = Invocation(
            arguments: ["guard", "PreToolUse"], environment: environment, input: { Data(input.utf8) })
        Thread.detachNewThread {
            let output = GuardCommand.run(invocation, transport: SocketTransport(), deadline: deadline)
            run.output.withLock { $0 = output }
        }
        return run
    }

    private func finished(_ run: Run, within seconds: Double) async -> String? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let output = run.output.withLock({ $0 }) { return output }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    @Test(arguments: [0, 1, 2])
    func incidentsBlockUntilApproval(index: Int) async throws {
        let server = try UnixSocketTelemetry(socketFile: URL(filePath: socket), clock: { .now })
        defer { server.stop() }
        var requests = server.requests().makeAsyncIterator()

        let run = start(Self.incidents[index])
        let request = try #require(await requests.next())

        #expect(await finished(run, within: 0.5) == nil)
        request.reply(.allow)
        #expect(await finished(run, within: 5) == "")
    }

    @Test(arguments: [0, 1, 2])
    func rejectedIncidentsAreDenied(index: Int) async throws {
        let server = try UnixSocketTelemetry(socketFile: URL(filePath: socket), clock: { .now })
        defer { server.stop() }
        var requests = server.requests().makeAsyncIterator()

        let run = start(Self.incidents[index])
        try #require(await requests.next()).reply(.deny("rechazado"))

        #expect(await finished(run, within: 5) == GuardCommandTests.denial("rechazado"))
    }

    @Test func missingSocketFailsClosed() async {
        let run = start(Self.incidents[1])

        #expect(await finished(run, within: 3) == GuardCommandTests.denial(GuardReasons.unreachable))
    }

    @Test func silentServerFailsClosedAtTheDeadline() async throws {
        let server = try UnixSocketTelemetry(socketFile: URL(filePath: socket), clock: { .now })
        defer { server.stop() }
        var requests = server.requests().makeAsyncIterator()

        let run = start(Self.incidents[1], deadline: .seconds(1))
        _ = await requests.next()

        #expect(await finished(run, within: 5) == GuardCommandTests.denial(GuardReasons.unreachable))
    }

    @Test func appQuittingFailsClosed() async throws {
        let server = try UnixSocketTelemetry(socketFile: URL(filePath: socket), clock: { .now })
        var requests = server.requests().makeAsyncIterator()

        let run = start(Self.incidents[0])
        _ = await requests.next()
        server.stop()

        #expect(await finished(run, within: 5) == GuardCommandTests.denial(GuardReasons.unreachable))
    }
}
