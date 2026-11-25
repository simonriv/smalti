import Foundation
import NeovimAdapter
import SmaltiCore
import Testing

@testable import NeovimAdapter

@Suite("MsgPack")
struct MsgPackTests {
    @Test func msgpackRoundTripsTypes() throws {
        let values: [MsgPackValue] = [
            .nil, .bool(true), .bool(false), .int(0), .int(127), .int(128), .int(70_000), .int(-1), .int(-200),
            .int(Int64.max), .double(1.5), .string(""), .string("línea \u{1F44D}"),
            .string(String(repeating: "x", count: 300)),
            .array([.int(1), .string("a")]), .map([.string("k"): .array([])]),
        ]

        for value in values {
            #expect(try MsgPack.decode(MsgPack.encode(value)).value == value, "\(value)")
        }
    }

    @Test func truncatedInputIsIncomplete() {
        let bytes = MsgPack.encode(.string("hola"))

        #expect(throws: MsgPackError.incomplete) { try MsgPack.decode(bytes.dropLast()) }
    }
}

@MainActor
@Suite("NeovimBridge", .serialized, .enabled(if: TestNeovim.isAvailable, "nvim is not installed"))
struct NeovimBridgeTests {
    private func file(_ name: String, lines: Int = 30, in nvim: TestNeovim) throws -> String {
        let path = nvim.folder.appending(path: name).path
        let text = (1...lines).map { "línea \($0)" }.joined(separator: "\n") + "\n"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func openJumpsToLine() async throws {
        let nvim = try TestNeovim()
        let path = try file("a.ts", in: nvim)
        let bridge = NeovimBridge()

        try await bridge.open(EditorTarget(path: path, line: 12, column: nil), socket: nvim.socket)

        #expect(await bridge.current(socket: nvim.socket) == EditorPosition(file: path, line: 12))
    }

    @Test func openPassesHostilePathAsArgument() async throws {
        let nvim = try TestNeovim()
        let path = try file("a b'\"$x\n<CR>|.txt", lines: 5, in: nvim)
        let bridge = NeovimBridge()

        try await bridge.open(EditorTarget(path: path, line: 3, column: 2), socket: nvim.socket)

        #expect(await bridge.current(socket: nvim.socket) == EditorPosition(file: path, line: 3))
        #expect(!FileManager.default.fileExists(atPath: nvim.folder.appending(path: "x").path))
    }

    @Test func lineBeyondTheEndGoesToTheLastLine() async throws {
        let nvim = try TestNeovim()
        let path = try file("short.ts", lines: 4, in: nvim)
        let bridge = NeovimBridge()

        try await bridge.open(EditorTarget(path: path, line: 400, column: nil), socket: nvim.socket)

        #expect(await bridge.current(socket: nvim.socket) == EditorPosition(file: path, line: 4))
    }

    @Test func currentReturnsFileAndLine() async throws {
        let path = "/private/tmp/smalti-nvim-start-\(UUID().uuidString.prefix(6)).ts"
        try "uno\ndos\ntres\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let nvim = try TestNeovim(arguments: ["+2", path])

        #expect(await NeovimBridge().current(socket: nvim.socket) == EditorPosition(file: path, line: 2))
    }

    @Test func deadSocketIsTypedError() async {
        do {
            try await NeovimBridge().open(
                EditorTarget(path: "/x", line: 1, column: nil), socket: "/private/tmp/nope.sock")
            Issue.record("a dead socket must fail")
        } catch {
            guard case .unreachable = error else {
                Issue.record("expected unreachable, got \(error)")
                return
            }
        }
        #expect(await NeovimBridge().current(socket: "/private/tmp/nope.sock") == nil)
    }

    @Test func currentTimesOutAt200ms() async throws {
        let server = try SilentSocketServer()
        let started = Date()

        let position = await NeovimBridge().current(socket: server.path)

        #expect(position == nil)
        #expect(Date().timeIntervalSince(started) < 1)
    }
}

/// Accepts connections and never answers, like a Neovim stuck in a prompt.
final class SilentSocketServer: @unchecked Sendable {
    let path = "/private/tmp/smalti-silent-\(UUID().uuidString.prefix(8)).sock"
    private let descriptor: Int32

    init() throws {
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: Array(path.utf8) + [0])
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
    }

    deinit {
        close(descriptor)
        unlink(path)
    }
}
