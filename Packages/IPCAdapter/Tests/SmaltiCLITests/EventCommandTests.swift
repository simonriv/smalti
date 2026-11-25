import Darwin
import Foundation
import SmaltiIPCProtocol
import Testing

@testable import smalti

@Suite("smalti event")
struct EventCommandTests {
    final class RecordingTransport: EventTransport, @unchecked Sendable {
        var sent: [(Data, String)] = []
        func send(_ line: Data, to socket: String, timeout: Duration) throws(TransportError) {
            sent.append((line, socket))
        }
    }

    private let environment = [
        "SMALTI_SOCKET": "/tmp/s.sock", "SMALTI_PANE_ID": "8D8AC610-566D-4EF0-9C22-186B2A5ED793",
    ]

    private func run(
        _ arguments: [String], environment: [String: String]? = nil, input: String = "{}",
        transport: any EventTransport = RecordingTransport()
    ) -> Int32 {
        EventCommand.run(
            Invocation(arguments: arguments, environment: environment ?? self.environment, input: { Data(input.utf8) }),
            transport: transport)
    }

    @Test func forwardsStdinAsPayload() throws {
        let transport = RecordingTransport()

        #expect(run(["event", "Stop"], input: #"{"session_id":"s1"}"#, transport: transport) == 0)

        let (line, socket) = try #require(transport.sent.first)
        let request = try IPCCodec.decodeRequest(line)
        #expect(socket == "/tmp/s.sock")
        #expect(request.hook == "Stop")
        #expect(request.pane == "8D8AC610-566D-4EF0-9C22-186B2A5ED793")
        #expect(String(decoding: request.payload, as: UTF8.self).contains("s1"))
    }

    /// F6: "Editados por Claude" finds the line from the text a file tool wrote, so that text has to reach the app.
    @Test func fileToolsKeepTheTextTheyWrote() throws {
        let edit =
            #"{"tool_name":"Edit","tool_input":{"file_path":"/w/a.ts","old_string":"x","new_string":"func a() {"}}"#
        let multi =
            #"{"tool_name":"MultiEdit","tool_input":{"file_path":"/w/b.ts","edits":[{"old_string":"y","new_string":"let b"}]}}"#
        let write = #"{"tool_name":"Write","tool_input":{"file_path":"/w/c.ts","content":"export {}"}}"#
        let notebook = #"{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/w/d.ipynb","new_source":"x"}}"#

        let kept = try [edit, multi, write, notebook].map { input in
            let object = try JSONSerialization.jsonObject(with: EventCommand.essentials(Data(input.utf8)))
            return try #require((object as? [String: Any])?["tool_input"] as? [String: Any])
        }

        #expect(kept[0]["new_string"] as? String == "func a() {")
        #expect(kept[0]["old_string"] == nil)
        #expect((kept[1]["edits"] as? [[String: String]])?.first?["new_string"] == "let b")
        #expect(kept[2]["content"] as? String == "export {}")
        #expect(kept[3]["notebook_path"] as? String == "/w/d.ipynb")
    }

    @Test func exitsZeroWithoutSocketVariable() {
        let transport = RecordingTransport()

        #expect(run(["event", "Stop"], environment: ["SMALTI_PANE_ID": "x"], transport: transport) == 0)
        #expect(transport.sent.isEmpty)
    }

    @Test func exitsZeroWithoutPaneVariable() {
        let transport = RecordingTransport()

        #expect(run(["event", "Stop"], environment: ["SMALTI_SOCKET": "/tmp/s"], transport: transport) == 0)
        #expect(transport.sent.isEmpty)
    }

    @Test func exitsZeroWhenAppIsGoneInUnderOneSecond() {
        let started = ContinuousClock.now
        let environment = ["SMALTI_SOCKET": "/tmp/smalti-no-existe-\(UUID()).sock", "SMALTI_PANE_ID": "x"]

        #expect(run(["event", "Stop"], environment: environment, transport: SocketTransport()) == 0)
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    /// An app that accepts but never answers cannot hold a hook past the timeout, whatever its length.
    @Test(.timeLimit(.minutes(1)))
    func silentServerIsLeftAfterTheTimeout() throws {
        let path = "/tmp/smalti-silent-\(UUID().uuidString.prefix(8)).sock"
        let listener = try #require(SilentListener(path: path))
        defer { listener.close() }
        let started = ContinuousClock.now

        try? SocketTransport().send(Data("{}\n".utf8), to: path, timeout: .seconds(1))

        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(900))
        #expect(elapsed < .seconds(2))
    }

    @Test func inputThatIsNotJSONTravelsAsAnEmptyPayload() throws {
        let transport = RecordingTransport()

        #expect(
            run(
                ["event", "Stop"], input: String(repeating: "a", count: IPCLimits.maxMessageBytes + 1),
                transport: transport) == 0)

        let (line, _) = try #require(transport.sent.first)
        #expect(String(decoding: try IPCCodec.decodeRequest(line).payload, as: UTF8.self) == "{}")
    }

    /// Only `event` reads stdin: `--version` from a terminal or a pipe left open must return at once.
    @Test func versionDoesNotReadInput() {
        var reads = 0
        let invocation = Invocation(
            arguments: ["--version"], environment: [:],
            input: {
                reads += 1
                return Data()
            })

        #expect(EventCommand.run(invocation, transport: RecordingTransport()) == 0)
        #expect(reads == 0)
    }

    @Test func eventWithoutSocketDoesNotReadInput() {
        var reads = 0
        let invocation = Invocation(
            arguments: ["event", "Stop"], environment: [:],
            input: {
                reads += 1
                return Data()
            })

        #expect(EventCommand.run(invocation, transport: RecordingTransport()) == 0)
        #expect(reads == 0)
    }

    @Test func versionSucceeds() {
        #expect(run(["--version"]) == 0)
    }

    @Test func unknownUsageIsAnError() {
        #expect(run(["otra-cosa"]) == 64)
        #expect(run(["event"]) == 64)
    }

    @Test func aHugePromptIsTrimmedNotDropped() throws {
        let transport = RecordingTransport()
        let huge = String(repeating: "a", count: IPCLimits.maxMessageBytes)
        let input = "{\"session_id\":\"s1\",\"prompt\":\"\(huge)\",\"tool_input\":{\"content\":\"\(huge)\"}}"

        #expect(run(["event", "UserPromptSubmit"], input: input, transport: transport) == 0)

        let (line, _) = try #require(transport.sent.first)
        let payload = try JSONSerialization.jsonObject(with: try IPCCodec.decodeRequest(line).payload) as? [String: Any]
        #expect(payload?["session_id"] as? String == "s1")
        #expect((payload?["prompt"] as? String)?.count == EventCommand.maxFieldLength)
        let tool = payload?["tool_input"] as? [String: Any]
        #expect((tool?["content"] as? String)?.count == EventCommand.maxFieldLength)
        #expect(line.count < IPCLimits.maxMessageBytes)
    }
}

/// Listens and accepts nothing: connections queue in the backlog and never get an answer.
final class SilentListener {
    private let fd: Int32
    private let path: String

    init?(path: String) {
        self.path = path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else { return nil }
    }

    func close() {
        Darwin.close(fd)
        unlink(path)
    }

}
