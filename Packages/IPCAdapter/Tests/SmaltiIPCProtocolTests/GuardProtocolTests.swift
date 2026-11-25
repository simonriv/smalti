import Foundation
import SmaltiIPCProtocol
import Testing

@Suite("Guard protocol")
struct GuardProtocolTests {
    @Test func guardRequestCarriesItsKind() throws {
        let request = IPCRequest(guardFor: "p1", hook: "PreToolUse", payload: Data(#"{"tool_name":"Bash"}"#.utf8))

        let decoded = try IPCCodec.decodeRequest(try IPCCodec.encode(request).dropLast())

        #expect(decoded.kind == IPCRequest.guardKind)
        #expect(decoded.hook == "PreToolUse")
        #expect(decoded.version == 1)
    }

    @Test func responseWithDecisionRoundTrips() throws {
        let response = IPCResponse(ok: true, error: nil, decision: .deny, reason: "no")

        let decoded = try IPCCodec.decodeResponse(try IPCCodec.encode(response))

        #expect(decoded == response)
    }

    @Test func oldResponseWithoutDecisionDecodes() throws {
        let decoded = try IPCCodec.decodeResponse(Data(#"{"ok":true,"error":null}"#.utf8))

        #expect(decoded == IPCResponse(ok: true, error: nil))
        #expect(decoded.decision == nil)
    }

    @Test func unknownDecisionIsMalformed() {
        #expect(throws: IPCCodecError.self) {
            try IPCCodec.decodeResponse(Data(#"{"ok":true,"error":null,"decision":"maybe"}"#.utf8))
        }
    }
}
