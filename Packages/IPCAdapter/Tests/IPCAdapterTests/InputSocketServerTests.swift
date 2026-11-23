import Darwin
import Foundation
@testable import IPCAdapter
import SmaltiCore
import Testing

/// A zsh-like client: one long-lived connection, lines both ways.
final class LineClient {
    let fd: Int32

    init?(path: String) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
    }

    deinit { close(fd) }

    func send(_ line: String) {
        let data = Data((line + "\n").utf8)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
    }

    /// One line from the server, or nil after `timeout`.
    func readLine(timeout: TimeInterval = 2) -> String? {
        var line = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var byte: UInt8 = 0
        while Date() < deadline {
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 50) > 0 else { continue }
            guard read(fd, &byte, 1) == 1 else { return nil }
            if byte == UInt8(ascii: "\n") { return String(decoding: line, as: UTF8.self) }
            line.append(byte)
        }
        return nil
    }
}

/// Collects what the server hands to the app, across its reader threads.
final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [(InputConnection, ShellPacket)] = []
    private var closed: [InputConnection] = []

    func add(_ connection: InputConnection, _ message: ShellPacket) {
        lock.withLock { messages.append((connection, message)) }
    }

    func close(_ connection: InputConnection) { lock.withLock { closed.append(connection) } }

    var all: [(InputConnection, ShellPacket)] { lock.withLock { messages } }
    var closedCount: Int { lock.withLock { closed.count } }

    func wait(for count: Int, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if all.count >= count { return true }
            usleep(5_000)
        }
        return false
    }
}

@Suite("InputSocketServer", .serialized)
struct InputSocketServerTests {
    private let path = "/tmp/smalti-input-\(UUID().uuidString.prefix(8)).sock"
    private let received = Received()

    private func start() throws -> InputSocketServer {
        let received = received
        let server = try InputSocketServer(socketFile: URL(filePath: path)) { connection, message in
            received.add(connection, message)
        }
        server.onClose = { received.close($0) }
        return server
    }

    @Test func decodesMessagesFromClient() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))

        client.send("line\t1\t/repo\t3\tgit")

        #expect(received.wait(for: 1))
        #expect(received.all.first?.1.message == .line(seq: 1, InputLine(text: "git", cursor: 3)))
    }

    @Test func responsesGoToTheirOwnConnection() throws {
        let server = try start()
        defer { server.stop() }
        let first = try #require(LineClient(path: path))
        let second = try #require(LineClient(path: path))
        first.send("line\t1\t/\t1\ta")
        #expect(received.wait(for: 1))
        second.send("line\t1\t/\t1\tb")
        #expect(received.wait(for: 2))

        for (connection, message) in received.all {
            if case .line(_, let line) = message.message { connection.send(.suggest(seq: 1, line.text + "!")) }
        }

        #expect(first.readLine() == "suggest\t1\ta!")
        #expect(second.readLine() == "suggest\t1\tb!")
    }

    @Test func closedConnectionIsForgotten() throws {
        let server = try start()
        defer { server.stop() }
        do {
            let client = try #require(LineClient(path: path))
            client.send("bye")
            #expect(received.wait(for: 1))
        }

        let deadline = Date().addingTimeInterval(2)
        while received.closedCount == 0 && Date() < deadline { usleep(5_000) }
        usleep(100_000)

        #expect(received.closedCount == 1)
    }

    /// Final review m5: the app can end a connection (its pane closed, or the shell was replaced by `exec zsh`
    /// while a child still holds the old socket): the shell side sees the end and the server forgets it.
    @Test func appCanCloseAConnection() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))
        client.send("hello\t\(UUID().uuidString)")
        #expect(received.wait(for: 1))

        try #require(received.all.first).0.close()

        let deadline = Date().addingTimeInterval(2)
        while received.closedCount == 0 && Date() < deadline { usleep(5_000) }
        #expect(received.closedCount == 1)
        #expect(client.readLine(timeout: 0.5) == nil)
    }

    @Test func unreadableLineIsDropped() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))

        client.send("nonsense")
        client.send("done\t2\t0")

        #expect(received.wait(for: 1))
        #expect(received.all.map(\.1.message) == [.done(seq: 2, exit: 0)])
    }

    @Test func clientThatNeverReadsDoesNotBlockServer() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))
        client.send("hello\t\(PaneID().description)")
        #expect(received.wait(for: 1))
        let connection = try #require(received.all.first?.0)
        let started = Date()

        for index in 0..<2_000 { connection.send(.suggest(seq: index, String(repeating: "x", count: 200))) }

        #expect(Date().timeIntervalSince(started) < 0.5)
    }

    @Test func oversizedLineIsSkipped() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))

        client.send("line\t1\t/\t0\t" + String(repeating: "a", count: InputSocketServer.maximumLineBytes + 10))
        client.send("done\t3\t1")

        #expect(received.wait(for: 1))
        #expect(received.all.map(\.1.message) == [.done(seq: 3, exit: 1)])
    }

    @Test func longPathThrowsWithPath() {
        let long = "/tmp/" + String(repeating: "x", count: 120) + ".sock"

        #expect(throws: IPCError.self) {
            _ = try InputSocketServer(socketFile: URL(filePath: long)) { _, _ in }
        }
    }

    @Test func socketIsOwnerOnly() throws {
        let server = try start()
        defer { server.stop() }

        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int

        #expect(mode == 0o600)
    }

    // MARK: Block 3 review

    /// C3: an answer for a shell that is gone never lands in whatever reused its descriptor.
    @Test func sendAfterCloseNeverReachesAReusedDescriptor() throws {
        let server = try start()
        defer { server.stop() }
        var connection: InputConnection?
        do {
            let client = try #require(LineClient(path: path))
            client.send("hello\t\(PaneID().description)")
            #expect(received.wait(for: 1))
            connection = received.all.first?.0
        }
        let deadline = Date().addingTimeInterval(2)
        while received.closedCount == 0 && Date() < deadline { usleep(5_000) }
        usleep(50_000)
        let file = FileManager.default.temporaryDirectory.appending(path: "smalti-reused-\(UUID())")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let reused = try FileHandle(forWritingTo: file)
        defer { try? reused.close() }

        let sent = connection?.send(.suggest(seq: 1, "git push --force"))

        #expect(sent == false)
        #expect(try Data(contentsOf: file).isEmpty)
    }

    /// C2: a message is written whole or not at all; one too big for the socket is refused.
    @Test func oversizedAnswerIsRefusedWhole() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))
        client.send("hello\t\(PaneID().description)")
        #expect(received.wait(for: 1))
        let connection = try #require(received.all.first?.0)

        let sent = connection.send(.suggest(seq: 1, String(repeating: "x", count: InputConnection.maximumMessageBytes)))
        let small = connection.send(.suggest(seq: 2, "ok"))

        #expect(!sent)
        #expect(small)
        #expect(client.readLine() == "suggest\t2\tok")
    }

    /// I6: `send` tells whether the whole message went out.
    @Test func sendReportsSuccess() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))
        client.send("hello\t\(PaneID().description)")
        #expect(received.wait(for: 1))

        #expect(received.all.first?.0.send(.specs(["git"])) == true)
    }

    /// I2: `bye` ends the connection even if the shell's socket stays open in a background child.
    @Test func byeClosesTheConnection() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))

        client.send("bye")

        let deadline = Date().addingTimeInterval(2)
        while received.closedCount == 0 && Date() < deadline { usleep(5_000) }
        #expect(received.closedCount == 1)
        _ = client
    }

    /// I2: Smalti's sockets never leak into the shells and generators it starts.
    @Test func descriptorsAreCloseOnExec() throws {
        let server = try start()
        defer { server.stop() }
        let client = try #require(LineClient(path: path))
        client.send("hello\t\(PaneID().description)")
        #expect(received.wait(for: 1))

        let descriptors = server.openDescriptors

        #expect(descriptors.count == 2)
        #expect(descriptors.allSatisfy { fcntl($0, F_GETFD) & FD_CLOEXEC != 0 })
    }
}
