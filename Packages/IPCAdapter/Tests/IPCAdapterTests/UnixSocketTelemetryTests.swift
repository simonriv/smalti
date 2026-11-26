import Foundation
import IPCAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import SmaltiIPCProtocol
import Testing

@MainActor
@Suite("Unix socket telemetry", .serialized)
struct UnixSocketTelemetryTests {
    private let directory = URL(filePath: "/tmp").appending(path: "smalti-ipc-\(UUID().uuidString.prefix(8))")
    private var socketFile: URL { directory.appending(path: "smalti.sock") }
    private var path: String { socketFile.path(percentEncoded: false) }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let pane = PaneID()

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func server() throws -> UnixSocketTelemetry {
        let now = self.now
        return try UnixSocketTelemetry(socketFile: socketFile, clock: { now }, texts: .spanish)
    }

    private func response(_ line: Data) async -> IPCResponse? {
        let path = self.path
        let data = await Task.detached { SocketClient.send(line, to: path) }.value
        return data.flatMap { try? IPCCodec.decodeResponse($0) }
    }

    @Test func serverDeliversEventFromSocket() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var events = telemetry.events().makeAsyncIterator()

        let answer = await response(
            SocketClient.request(
                pane: pane.description, hook: "Stop", payload: #"{"session_id":"8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"}"#
            ))
        let event = await events.next()

        #expect(answer == IPCResponse(ok: true, error: nil))
        #expect(
            event == AgentEvent(pane: pane, hook: .stop, at: now, sessionID: "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a"))
    }

    @Test func serverRejectsUnknownVersion() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        let line = Data(#"{"v":2,"kind":"event","pane":"\#(pane)","hook":"Stop","payload":{}}"#.utf8 + [10])

        #expect(await response(line)?.ok == false)
        #expect(await response(SocketClient.request(pane: pane.description, hook: "Stop"))?.ok == true)
    }

    @Test func serverRejectsUnknownPaneFormat() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }

        #expect(await response(SocketClient.request(pane: "no-es-uuid", hook: "Stop"))?.ok == false)
    }

    @Test func serverRejectsUnknownHook() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }

        #expect(await response(SocketClient.request(pane: pane.description, hook: "PreCompact"))?.ok == false)
    }

    @Test func serverRejectsMessageOver1MB() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        let huge = String(repeating: "a", count: IPCLimits.maxMessageBytes)
        let line = SocketClient.request(pane: pane.description, hook: "Stop", payload: #"{"prompt":"\#(huge)"}"#)

        #expect(await response(line)?.ok == false)
        #expect(await response(SocketClient.request(pane: pane.description, hook: "Stop"))?.ok == true)
    }

    @Test func staleSocketFileIsReplaced() async throws {
        SocketClient.leaveStaleSocket(at: path)
        #expect(FileManager.default.fileExists(atPath: path))

        let telemetry = try server()
        defer { telemetry.stop() }

        #expect(await response(SocketClient.request(pane: pane.description, hook: "Stop"))?.ok == true)
    }

    @Test func secondServerLeavesLiveSocketAlone() async throws {
        let first = try server()
        defer { first.stop() }

        #expect(throws: IPCError.socketInUse(path: path)) { _ = try server() }
        #expect(await response(SocketClient.request(pane: pane.description, hook: "Stop"))?.ok == true)
    }

    @Test func requestWrittenInPiecesWithoutANewlineIsRead() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        var line = SocketClient.request(pane: pane.description, hook: "Stop")
        line.removeLast()
        let path = self.path
        let pieces = [line.prefix(10), line.dropFirst(10)].map { Data($0) }

        let answer = await Task.detached { SocketClient.send(pieces: pieces, to: path) }.value

        #expect(answer.flatMap { try? IPCCodec.decodeResponse($0) }?.ok == true)
    }

    @Test func aSilentClientDoesNotHoldUpOthers() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        let path = self.path
        let silent = Task.detached { SocketClient.holdOpenSilently(path, for: .milliseconds(900)) }
        try await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now

        let answer = await response(SocketClient.request(pane: pane.description, hook: "Stop"))

        #expect(answer?.ok == true)
        #expect(ContinuousClock.now - started < .milliseconds(400))
        await silent.value
    }

    @Test func pathLongerThanASocketAddressIsRefused() {
        let long = URL(filePath: "/tmp/" + String(repeating: "x", count: 120) + ".sock")

        #expect(throws: IPCError.self) {
            _ = try UnixSocketTelemetry(socketFile: long, clock: { .now }, texts: .spanish)
        }
    }

    @Test func socketFileIs0600() throws {
        let telemetry = try server()
        defer { telemetry.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    @Test func stopRemovesTheSocketFile() throws {
        try server().stop()

        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func socketSatisfiesTheTelemetryContract() async throws {
        let telemetry = try server()
        defer { telemetry.stop() }
        let path = self.path
        await TelemetrySourceContract.verify {
            (
                telemetry,
                { event in
                    let line = SocketClient.request(
                        pane: event.pane.description, hook: event.hook.rawValue,
                        payload: #"{"session_id":"\#(event.sessionID ?? "")"}"#)
                    _ = await Task.detached { SocketClient.send(line, to: path) }.value
                }
            )
        }
    }
}
