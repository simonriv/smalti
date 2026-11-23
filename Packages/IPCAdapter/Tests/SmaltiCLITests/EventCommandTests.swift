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
            Invocation(arguments: arguments, environment: environment ?? self.environment, input: Data(input.utf8)),
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

    @Test func oversizedInputIsDroppedQuietly() {
        let transport = RecordingTransport()
        let huge = String(repeating: "a", count: IPCLimits.maxMessageBytes + 1)

        #expect(run(["event", "Stop"], input: huge, transport: transport) == 0)
        #expect(transport.sent.isEmpty)
    }

    @Test func versionSucceeds() {
        #expect(run(["--version"]) == 0)
    }

    @Test func unknownUsageIsAnError() {
        #expect(run(["otra-cosa"]) == 64)
        #expect(run(["event"]) == 64)
    }
}
