import Foundation
import SmaltiIPCProtocol
import Testing

@Suite("IPC codec")
struct IPCCodecTests {
    private let payload = Data(#"{"session_id":"7f3a","hook_event_name":"Stop","extra":{"a":[1,2]}}"#.utf8)

    @Test func requestRoundTripsAndKeepsThePayloadObject() throws {
        let request = IPCRequest(pane: "8D8AC610-566D-4EF0-9C22-186B2A5ED793", hook: "Stop", payload: payload)

        let line = try IPCCodec.encode(request)
        let decoded = try IPCCodec.decodeRequest(line)

        #expect(decoded.version == IPCLimits.version)
        #expect(decoded.kind == "event")
        #expect(decoded.pane == request.pane)
        #expect(decoded.hook == "Stop")
        let object = try JSONSerialization.jsonObject(with: decoded.payload) as? [String: Any]
        #expect(object?["session_id"] as? String == "7f3a")
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(String(decoding: line, as: UTF8.self).contains(#""payload":{"#))
    }

    @Test func invalidPayloadTravelsAsAnEmptyObject() throws {
        let request = IPCRequest(pane: "p", hook: "Stop", payload: Data("no es json".utf8))

        let decoded = try IPCCodec.decodeRequest(try IPCCodec.encode(request))

        #expect(String(decoding: decoded.payload, as: UTF8.self) == "{}")
    }

    @Test func oversizedMessageIsRejected() {
        let huge = Data(repeating: UInt8(ascii: "a"), count: IPCLimits.maxMessageBytes + 1)

        #expect(throws: IPCCodecError.self) { try IPCCodec.decodeRequest(huge) }
    }

    @Test func malformedLineIsRejected() {
        #expect(throws: IPCCodecError.self) { try IPCCodec.decodeRequest(Data("{".utf8)) }
    }

    @Test func responseRoundTrips() throws {
        let response = IPCResponse(ok: false, error: "unknown pane")

        #expect(try IPCCodec.decodeResponse(try IPCCodec.encode(response)) == response)
    }

    @Test func limitsArePinned() {
        #expect(IPCLimits.version == 1)
        #expect(IPCLimits.maxMessageBytes == 1_048_576)
    }
}
