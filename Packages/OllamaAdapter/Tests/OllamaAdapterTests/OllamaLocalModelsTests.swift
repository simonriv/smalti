import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Synchronization
import Testing

@testable import OllamaAdapter

/// Answers requests by host, so tests running in parallel never see each other's routes.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Route: Sendable {
        let status: Int
        let body: String
        var delay: Duration = .zero
    }

    static let routes = Mutex<[String: Route]>([:])

    static func serve(_ routes: [String: Route]) -> URL {
        let host = "ollama-\(UUID().uuidString.lowercased()).test"
        Self.routes.withLock { table in
            for (path, route) in routes { table[host + path] = route }
        }
        return URL(string: "http://\(host)") ?? URL(filePath: "/")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = (request.url?.host() ?? "") + (request.url?.path() ?? "")
        let route = Self.routes.withLock { $0[key] } ?? Route(status: 404, body: "")
        let client = client
        let url = request.url
        Thread.detachNewThread { [self] in
            Thread.sleep(
                forTimeInterval: Double(route.delay.components.seconds) + Double(route.delay.components.attoseconds)
                    / 1e18)
            guard let url,
                let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: nil, headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(route.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@Suite("OllamaLocalModels")
struct OllamaLocalModelsTests {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }()

    private static let ps =
        #"{"models":[{"name":"qwen3.5:9b","size":6549825126,"size_vram":6549825126,"context_length":65536,"details":{"quantization_level":"Q4_K_M"}}]}"#
    private static let tags =
        #"{"models":[{"name":"qwen3.5:9b","size":6549825126,"modified_at":"2026-11-20T10:00:00.123456789-05:00"},{"name":"nomic-embed-text:latest","size":287309824,"modified_at":"2026-11-21T10:00:00.5-05:00"}]}"#

    private func models(_ routes: [String: StubProtocol.Route]) async -> LocalModelsReport {
        await OllamaLocalModels(baseURL: StubProtocol.serve(routes), session: session).current()
    }

    @Test func loadedModelsComeFromPs() async {
        let report = await models([
            "/api/ps": .init(status: 200, body: Self.ps), "/api/tags": .init(status: 200, body: Self.tags),
        ])

        guard case .available(let loaded, _) = report else {
            Issue.record("expected models")
            return
        }
        #expect(
            loaded == [
                LocalModel(
                    name: "qwen3.5:9b", quantization: "Q4_K_M", bytes: 6_549_825_126, vramBytes: 6_549_825_126,
                    contextLength: 65_536, downloadedAt: nil)
            ])
    }

    @Test func onDiskExcludesLoadedAndKeepsDownloadDate() async {
        let report = await models([
            "/api/ps": .init(status: 200, body: Self.ps), "/api/tags": .init(status: 200, body: Self.tags),
        ])

        guard case .available(_, let onDisk) = report else {
            Issue.record("expected models")
            return
        }
        #expect(onDisk.map(\.name) == ["nomic-embed-text:latest"])
        #expect(onDisk.first?.downloadedAt == Date(timeIntervalSince1970: 1_795_273_200.5))
    }

    @Test func missingContextLengthIsNil() async {
        let ps = #"{"models":[{"name":"m","size":10,"details":{}}]}"#

        let report = await models([
            "/api/ps": .init(status: 200, body: ps), "/api/tags": .init(status: 200, body: #"{"models":[]}"#),
        ])

        guard case .available(let loaded, _) = report else {
            Issue.record("expected models")
            return
        }
        #expect(loaded.first?.contextLength == nil)
        #expect(loaded.first?.quantization == nil)
    }

    @Test func failingTagsLeavesDiskEmpty() async {
        let report = await models([
            "/api/ps": .init(status: 200, body: Self.ps), "/api/tags": .init(status: 500, body: ""),
        ])

        guard case .available(let loaded, let onDisk) = report else {
            Issue.record("expected models")
            return
        }
        #expect(loaded.count == 1)
        #expect(onDisk.isEmpty)
    }

    @Test func connectionRefusedIsUnavailable() async {
        let report = await OllamaLocalModels(baseURL: URL(string: "http://127.0.0.1:1") ?? URL(filePath: "/")).current()

        #expect(report == .unavailable)
    }

    @Test func slowServerTimesOutUnavailable() async {
        let clock = ContinuousClock()
        var report = LocalModelsReport.unavailable

        let elapsed = await clock.measure {
            report = await models(["/api/ps": .init(status: 200, body: Self.ps, delay: .seconds(3))])
        }

        #expect(report == .unavailable)
        #expect(elapsed < .seconds(2))
    }

    @Test func badJsonIsUnavailable() async {
        #expect(await models(["/api/ps": .init(status: 200, body: "{nope")]) == .unavailable)
    }

    @Test func errorStatusIsUnavailable() async {
        #expect(await models(["/api/ps": .init(status: 500, body: "")]) == .unavailable)
    }

    @Test func adapterHonoursTheContract() async {
        await LocalModelsContract.verify(
            OllamaLocalModels(
                baseURL: StubProtocol.serve([
                    "/api/ps": .init(status: 200, body: Self.ps), "/api/tags": .init(status: 200, body: Self.tags),
                ]),
                session: session))
    }
}
