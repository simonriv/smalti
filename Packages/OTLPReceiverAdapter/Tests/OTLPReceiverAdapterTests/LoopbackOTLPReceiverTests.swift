import Darwin
import Foundation
import OTLPReceiverAdapter
import SmaltiCore
import Synchronization
import Testing

private struct Undecodable: Error {}

/// A decoder for the socket tests: the body is the session id, and "bad" cannot be decoded.
private let decodeSessionID: @Sendable (Data) throws -> [TelemetryEvent] = { body in
    let text = String(decoding: body, as: UTF8.self)
    if text == "bad" { throw Undecodable() }
    return [
        .apiRequest(
            APIRequest(
                sessionID: text, sequence: nil, at: Date(timeIntervalSince1970: 0), model: nil,
                durationMilliseconds: 1, costMicroUSD: 1))
    ]
}

@MainActor
@Suite("Loopback OTLP receiver", .serialized)
final class LoopbackOTLPReceiverTests {
    private var batches: [[TelemetryEvent]] = []
    private var receivers: [LoopbackOTLPReceiver] = []

    deinit {
        let receivers = self.receivers
        Task { @MainActor in receivers.forEach { $0.stop() } }
    }

    private func started(idleTimeout: Duration = .seconds(30), maximumBody: Int = 4 << 20, token: String = "secret")
        throws -> (LoopbackOTLPReceiver, TelemetryEndpoint)
    {
        let receiver = LoopbackOTLPReceiver(
            decode: decodeSessionID, idleTimeout: idleTimeout, maximumBody: maximumBody, token: { token })
        receivers.append(receiver)
        let endpoint = try receiver.start { [weak self] in self?.batches.append($0) }
        return (receiver, endpoint)
    }

    private func client(_ endpoint: TelemetryEndpoint) throws -> TestHTTPClient {
        try #require(TestHTTPClient(port: endpoint.port))
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func sessions() -> [String] {
        batches.flatMap { $0 }.compactMap {
            guard case .apiRequest(let request) = $0 else { return nil }
            return request.sessionID
        }
    }

    // MARK: C1 · loopback only

    @Test func listensOnlyOnLoopback() throws {
        let (receiver, endpoint) = try started()

        #expect(receiver.boundAddress == "127.0.0.1")
        #expect(endpoint.port > 0)
    }

    @Test func connectViaLanAddressFails() throws {
        let (_, endpoint) = try started()
        let lan = try #require(lanAddress(), "this Mac has no non-loopback IPv4 address")

        let client = TestHTTPClient(address: lan, port: endpoint.port)

        #expect(client == nil)
        #expect(TestHTTPClient.lastConnectError == ECONNREFUSED)
    }

    @Test func connectViaIPv6LoopbackFails() throws {
        let (_, endpoint) = try started()

        #expect(TestHTTPClient(address: "::1", port: endpoint.port) == nil)
    }

    // MARK: C3 · HTTP

    @Test func acceptsLogsWithToken() async throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(body: "s1", token: endpoint.token))

        #expect(client.response() == .init(status: 200, body: "{}"))
        await eventually { !batches.isEmpty }
        #expect(sessions() == ["s1"])
    }

    @Test func endpointCarriesTheToken() throws {
        #expect(try started(token: "abc").1.token == "abc")
    }

    @Test func rejectsMissingToken() async throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(body: "s1", token: nil))

        #expect(client.response()?.status == 401)
        try await Task.sleep(for: .milliseconds(50))
        #expect(batches.isEmpty)
    }

    @Test func rejectsWrongToken() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(body: "s1", token: "secreT"))

        #expect(client.response()?.status == 401)
    }

    @Test func unknownPathIs404() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(path: "/v1/metrics", body: "s1", token: endpoint.token))

        #expect(client.response()?.status == 404)
    }

    @Test func getIs405() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send("GET /v1/logs HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer \(endpoint.token)\r\n\r\n")

        #expect(client.response()?.status == 405)
    }

    @Test func gzipIs415() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(body: "s1", token: endpoint.token, extraHeaders: ["Content-Encoding: gzip"]))

        #expect(client.response()?.status == 415)
    }

    @Test func identityEncodingIsAccepted() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(
            TestHTTPClient.post(body: "s1", token: endpoint.token, extraHeaders: ["Content-Encoding: identity"]))

        #expect(client.response()?.status == 200)
    }

    @Test func missingContentLengthIs411() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send("POST /v1/logs HTTP/1.1\r\nAuthorization: Bearer \(endpoint.token)\r\n\r\ns1")

        #expect(client.response()?.status == 411)
        #expect(client.isClosedByServer())
    }

    @Test func chunkedIs411() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(
            "POST /v1/logs HTTP/1.1\r\nAuthorization: Bearer \(endpoint.token)\r\nTransfer-Encoding: chunked\r\n\r\n2\r\ns1\r\n0\r\n\r\n"
        )

        #expect(client.response()?.status == 411)
    }

    @Test func oversizedBodyIs413WithoutReadingIt() throws {
        let (_, endpoint) = try started(maximumBody: 10)
        let client = try client(endpoint)

        client.send(
            "POST /v1/logs HTTP/1.1\r\nAuthorization: Bearer \(endpoint.token)\r\nContent-Length: 11\r\n\r\n")

        #expect(client.response()?.status == 413)
        #expect(client.isClosedByServer())
    }

    @Test func bodyAtTheLimitIsAccepted() throws {
        let (_, endpoint) = try started(maximumBody: 10)
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(body: "0123456789", token: endpoint.token))

        #expect(client.response()?.status == 200)
    }

    @Test func undecodableBodyIs400() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(TestHTTPClient.post(body: "bad", token: endpoint.token))

        #expect(client.response()?.status == 400)
    }

    @Test func garbageRequestLineIs400() throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send("HELLO\r\n\r\n")

        #expect(client.response()?.status == 400)
    }

    @Test func keepAliveServesThreeRequests() async throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        for session in ["a", "b", "c"] {
            client.send(TestHTTPClient.post(body: session, token: endpoint.token))
            #expect(client.response()?.status == 200)
        }

        await eventually { sessions().count == 3 }
        #expect(sessions() == ["a", "b", "c"])
    }

    @Test func answersTwoPipelinedRequests() async throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)

        client.send(
            TestHTTPClient.post(body: "a", token: endpoint.token)
                + TestHTTPClient.post(body: "b", token: endpoint.token))

        #expect(client.response()?.status == 200)
        #expect(client.response()?.status == 200)
        await eventually { sessions().count == 2 }
        #expect(sessions() == ["a", "b"])
    }

    @Test func assemblesRequestSplitAcrossReads() async throws {
        let (_, endpoint) = try started()
        let client = try client(endpoint)
        let request = Data(TestHTTPClient.post(body: "split-session", token: endpoint.token).utf8)

        for start in stride(from: 0, to: request.count, by: 7) {
            client.send(request[start..<min(start + 7, request.count)])
            usleep(2_000)
        }

        #expect(client.response()?.status == 200)
        await eventually { !batches.isEmpty }
        #expect(sessions() == ["split-session"])
    }

    @Test func idleConnectionClosesAfterTimeout() throws {
        let (_, endpoint) = try started(idleTimeout: .milliseconds(200))
        let client = try client(endpoint)

        #expect(client.isClosedByServer())
    }

    @Test func seventeenthConnectionIsRefused() throws {
        let (_, endpoint) = try started()
        let open = try (0..<LoopbackOTLPReceiver.maximumConnections).map { _ in try client(endpoint) }
        usleep(100_000)

        let extra = try client(endpoint)

        #expect(extra.isClosedByServer())
        open[0].send(TestHTTPClient.post(body: "s", token: endpoint.token))
        #expect(open[0].response()?.status == 200)
    }

    @Test func stopClosesOpenConnections() throws {
        let (receiver, endpoint) = try started()
        let client = try client(endpoint)
        usleep(50_000)

        receiver.stop()

        #expect(client.isClosedByServer())
        #expect(TestHTTPClient(port: endpoint.port) == nil)
    }

    @Test func restartGivesNewPortAndToken() throws {
        let tokens = Mutex(["one", "two"])
        let receiver = LoopbackOTLPReceiver(decode: decodeSessionID, token: { tokens.withLock { $0.removeFirst() } })
        receivers.append(receiver)
        let first = try receiver.start { _ in }
        receiver.stop()

        let second = try receiver.start { _ in }

        #expect(first.token == "one")
        #expect(second.token == "two")
        #expect(TestHTTPClient(port: second.port) != nil)
    }

    @Test func randomTokensAreLongAndDistinct() {
        let tokens = (0..<20).map { _ in LoopbackOTLPReceiver.randomToken() }

        #expect(Set(tokens).count == 20)
        #expect(tokens.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) })
    }
}
