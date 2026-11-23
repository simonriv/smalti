import Darwin
import FigCompletionAdapter
import Foundation
import SmaltiCore
import Testing

/// Final review I1: a generator never reaches the network (Fig's `npm install` one asks registries about what was
/// typed). Checked against a listener on loopback, so the test itself stays off the network.
@Suite("Generator runner", .serialized)
struct GeneratorRunnerTests {
    private let runner = GeneratorRunner(timeout: .seconds(5))

    @Test func shellGeneratorCannotConnect() async throws {
        let port = try LoopbackListener()

        let output = try await runner.run(shell: "/usr/bin/nc -z 127.0.0.1 \(port.number); echo $?", in: "/tmp")

        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "0")
    }

    @Test func argumentGeneratorCannotConnect() async throws {
        let port = try LoopbackListener()

        let output = try await runner.run(arguments: ["/usr/bin/nc", "-z", "127.0.0.1", "\(port.number)"], in: "/tmp")

        #expect(output.status != 0)
    }

    /// Final review m3: a timed-out generator leaves no process behind: not its pipeline, not its background jobs.
    @Test func timeoutKillsTheWholePipeline() async throws {
        let marker = "\(Int.random(in: 100_000...999_999)).5"
        let quick = GeneratorRunner(timeout: .seconds(1))

        await #expect(throws: CompletionError.self) {
            _ = try await quick.run(shell: "/bin/sleep \(marker) & /bin/sleep \(marker) | /bin/cat", in: "/tmp")
        }
        try await Task.sleep(for: .milliseconds(500))

        #expect(try Self.processes(matching: "sleep \(marker)") == 0)
    }

    /// A background child that keeps the output pipe open does not keep Smalti's read end open after the result.
    @Test func resultReleasesTheOutputPipe() async throws {
        let marker = "\(Int.random(in: 100_000...999_999)).5"
        let before = try Self.openDescriptors()

        let output = try await runner.run(shell: "/bin/sleep \(marker) & echo hi", in: "/tmp")
        try await Task.sleep(for: .milliseconds(100))
        let after = try Self.openDescriptors()
        _ = try? Process.run(URL(filePath: "/usr/bin/pkill"), arguments: ["-f", "sleep \(marker)"])

        #expect(output.stdout == "hi\n")
        #expect(after <= before)
    }

    private static func openDescriptors() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }

    private static func processes(matching pattern: String) throws -> Int {
        let pgrep = Process()
        pgrep.executableURL = URL(filePath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", pattern]
        let output = Pipe()
        pgrep.standardOutput = output
        try pgrep.run()
        pgrep.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").count
    }

    @Test func localCommandsStillRun() async throws {
        let output = try await runner.run(shell: "echo hola", in: "/tmp")

        #expect(output.stdout == "hola\n")
    }
}

/// A TCP listener on 127.0.0.1 with a free port, closed when released.
private final class LoopbackListener {
    let number: UInt16
    private let fd: Int32

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        self.fd = fd
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                bind(fd, pointer, length) == 0 && listen(fd, 4) == 0 && getsockname(fd, pointer, &length) == 0
            }
        }
        guard bound else {
            close(fd)
            throw POSIXError(.EADDRNOTAVAIL)
        }
        number = UInt16(bigEndian: address.sin_port)
    }

    deinit { close(fd) }
}
