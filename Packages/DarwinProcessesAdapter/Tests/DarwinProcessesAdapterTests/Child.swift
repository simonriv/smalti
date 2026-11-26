import Foundation

/// A process the test starts itself and always ends: the only kind these tests ever signal. Loopback addresses
/// and ephemeral ports only, so the macOS firewall never asks.
final class Child {
    let process = Process()
    private let output = Pipe()
    private(set) var lines: [String] = []

    var pid: Int32 { process.processIdentifier }

    /// `python3 -c <script>` with its own process group, so a test that times out can end the whole group.
    init(python script: String, directory: URL? = nil) throws {
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", script]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if let directory { process.currentDirectoryURL = directory }
        try process.run()
        setpgid(process.processIdentifier, process.processIdentifier)
    }

    /// Waits for `count` lines on its standard output (ports it printed, "ready").
    func waitForLines(_ count: Int, timeout: TimeInterval = 10) throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while lines.count < count, Date() < deadline {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            lines = String(decoding: buffer, as: UTF8.self).split(separator: "\n").map(String.init)
        }
        guard lines.count >= count else { throw ChildError.noOutput(lines) }
        return lines
    }

    /// Ends it and its group, whatever it ignores.
    func end() {
        guard process.isRunning else { return }
        kill(-pid, SIGKILL)
        kill(pid, SIGKILL)
        process.waitUntilExit()
    }

    deinit { end() }

    enum ChildError: Error { case noOutput([String]) }

    /// Listens on TCP 127.0.0.1 and ::1 and on UDP 127.0.0.1, all on ephemeral ports, prints the three ports and
    /// sleeps. With `ignoringTerm`, SIGTERM does nothing.
    static func listener(ignoringTerm: Bool = false) throws -> Child {
        try Child(python: """
            import socket, time, signal
            \(ignoringTerm ? "signal.signal(signal.SIGTERM, signal.SIG_IGN)" : "")
            a = socket.socket(socket.AF_INET, socket.SOCK_STREAM); a.bind(("127.0.0.1", 0)); a.listen()
            b = socket.socket(socket.AF_INET6, socket.SOCK_STREAM); b.bind(("::1", 0)); b.listen()
            c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); c.bind(("127.0.0.1", 0))
            print(a.getsockname()[1]); print(b.getsockname()[1]); print(c.getsockname()[1])
            time.sleep(600)
            """)
    }

    static func sleeper(ignoringTerm: Bool = false, directory: URL? = nil) throws -> Child {
        let child = try Child(python: """
            import time, signal
            \(ignoringTerm ? "signal.signal(signal.SIGTERM, signal.SIG_IGN)" : "")
            print("ready")
            time.sleep(600)
            """, directory: directory)
        _ = try child.waitForLines(1)
        return child
    }

    static func spinner() throws -> Child {
        let child = try Child(python: "print('ready')\nwhile True: pass")
        _ = try child.waitForLines(1)
        return child
    }
}
