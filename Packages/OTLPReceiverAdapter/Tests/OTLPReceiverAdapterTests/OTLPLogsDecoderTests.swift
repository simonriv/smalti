import Foundation
import OTLPReceiverAdapter
import SmaltiCore
import Testing

@Suite("OTLP logs decoder")
struct OTLPLogsDecoderTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? .distantPast
    }

    @Test func decodesAPIRequest() throws {
        let events = try OTLPLogsDecoder.decode(try fixture("api-request"))

        #expect(
            events == [
                .apiRequest(
                    APIRequest(
                        sessionID: "5f0c8a7e-1b2d-4c3e-9f00-aa11bb22cc33", sequence: 3,
                        at: iso("2026-11-25T15:42:07.123Z"), model: "claude-opus-5-5", durationMilliseconds: 1400,
                        costMicroUSD: 12345))
            ])
    }

    @Test func decodesAPIErrorWithAndWithoutStatus() throws {
        let events = try OTLPLogsDecoder.decode(try fixture("api-error"))

        #expect(
            events == [
                .apiError(
                    APIError(
                        sessionID: "5f0c8a7e-1b2d-4c3e-9f00-aa11bb22cc33", sequence: 4,
                        at: iso("2026-11-25T15:43:00.000Z"),
                        model: "claude-opus-5-5", statusCode: 429)),
                .apiError(
                    APIError(
                        sessionID: "5f0c8a7e-1b2d-4c3e-9f00-aa11bb22cc33", sequence: 5,
                        at: iso("2026-11-25T15:43:00.000Z"),
                        model: "claude-opus-5-5", statusCode: nil)),
            ])
    }

    @Test func intValueAsNumberDoubleDurationAndCostFallback() throws {
        let events = try OTLPLogsDecoder.decode(try fixture("int-as-number"))

        #expect(
            events == [
                .apiRequest(
                    APIRequest(
                        sessionID: "s-num", sequence: 7, at: Date(timeIntervalSince1970: 1_795_000_000), model: nil,
                        durationMilliseconds: 1401, costMicroUSD: 12300))
            ])
    }

    @Test func nameFromBodyAndTimeFromTimeUnixNano() throws {
        let events = try OTLPLogsDecoder.decode(try fixture("body-only-name"))

        guard case .apiRequest(let request) = try #require(events.first) else {
            Issue.record("not an api_request: \(events)")
            return
        }
        #expect(request.at == Date(timeIntervalSince1970: 1_795_000_000))
        #expect(events.count == 1)
    }

    @Test func mixedBatchKeepsOnlyReadableAPIEvents() throws {
        let events = try OTLPLogsDecoder.decode(try fixture("mixed-batch"))

        #expect(events.count == 2)
        #expect(events.map(\.kind) == ["request", "error"])
    }

    @Test func rejectsNonJSON() {
        #expect(throws: OTLPDecodeError.self) { try OTLPLogsDecoder.decode(Data("not json".utf8)) }
    }

    @Test func rejectsJSONWithoutResourceLogs() {
        #expect(throws: OTLPDecodeError.notLogsRequest) {
            try OTLPLogsDecoder.decode(Data(#"{"resourceSpans":[]}"#.utf8))
        }
    }

    @Test func emptyResourceLogsIsAnEmptyBatch() throws {
        #expect(try OTLPLogsDecoder.decode(Data(#"{"resourceLogs":[]}"#.utf8)).isEmpty)
    }

    @Test func receiverDecodesWithItByDefault() async throws {
        let receiver = await LoopbackOTLPReceiver()
        let endpoint = try await receiver.start { _ in }
        defer { Task { @MainActor in receiver.stop() } }
        let client = try #require(TestHTTPClient(port: endpoint.port))

        client.send(TestHTTPClient.post(body: "not json", token: endpoint.token))

        #expect(client.response()?.status == 400)
    }
    // MARK: Review 1

    private func one(_ attributes: String, time: String = "\"1795000000000000000\"") -> Data {
        Data(
            """
            {"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":\(time),"attributes":[\(attributes)]}]}]}]}
            """.utf8)
    }

    private let base = """
        {"key":"event.name","value":{"stringValue":"api_request"}},{"key":"session.id","value":{"stringValue":"s"}}
        """

    @Test(arguments: [
        #"{"key":"cost_usd","value":{"doubleValue":1e20}},{"key":"duration_ms","value":{"intValue":"5"}}"#,
        #"{"key":"duration_ms","value":{"doubleValue":1e30}}"#,
        #"{"key":"duration_ms","value":{"intValue":"-5"}}"#,
        #"{"key":"duration_ms","value":{"intValue":"5"}},{"key":"cost_usd_micros","value":{"intValue":"-1"}}"#,
    ])
    func outOfRangeNumbersSkipTheRecord(numbers: String) throws {
        #expect(try OTLPLogsDecoder.decode(one(base + "," + numbers)).isEmpty)
    }

    @Test func unreadableStatusCodeStillCountsTheError() throws {
        let attributes = """
            {"key":"event.name","value":{"stringValue":"api_error"}},{"key":"session.id","value":{"stringValue":"s"}},\
            {"key":"status_code","value":{"stringValue":"undefined"}}
            """

        let events = try OTLPLogsDecoder.decode(one(attributes))

        guard case .apiError(let error) = try #require(events.first) else {
            Issue.record("not an api_error")
            return
        }
        #expect(error.statusCode == nil)
    }

    @Test func unreadableTimestampFallsBackToTimeUnixNano() throws {
        let attributes =
            base
            + #",{"key":"event.timestamp","value":{"stringValue":"yesterday"}},{"key":"duration_ms","value":{"intValue":"5"}}"#

        let events = try OTLPLogsDecoder.decode(one(attributes))

        guard case .apiRequest(let request) = try #require(events.first) else {
            Issue.record("not an api_request")
            return
        }
        #expect(request.at == Date(timeIntervalSince1970: 1_795_000_000))
    }

    @Test func prefixedEventNameIsAccepted() throws {
        let attributes = """
            {"key":"event.name","value":{"stringValue":"claude_code.api_request"}},\
            {"key":"session.id","value":{"stringValue":"s"}},{"key":"duration_ms","value":{"intValue":"5"}}
            """

        #expect(try OTLPLogsDecoder.decode(one(attributes)).count == 1)
    }
}

extension TelemetryEvent {
    fileprivate var kind: String {
        switch self {
        case .apiRequest: "request"
        case .apiError: "error"
        }
    }

}
