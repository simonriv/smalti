import DarwinProcessesAdapter
import Foundation
import SmaltiCore
import Testing

/// C1 of F8: the listening ports match lsof's (TCP in LISTEN plus unconnected UDP), for this test's own listeners
/// and for every process of the user.
@Suite("Listening ports match lsof", .serialized)
struct LsofParityTests {
    private let ports = DarwinListeningPorts()

    struct Entry: Hashable, CustomStringConvertible {
        let pid: Int32
        let transport: Transport
        let port: UInt16
        let address: String

        var description: String { "\(pid) \(transport.rawValue) \(address):\(port)" }
    }

    @Test func testListenersMatchLsof() async throws {
        let child = try Child.listener()
        defer { child.end() }
        let printed = try child.waitForLines(3).compactMap { UInt16($0) }

        let ours = Set(await ports.current().filter { $0.pid == child.pid }.map(Self.entry))
        let lsof = try Self.lsof().filter { $0.pid == child.pid }

        #expect(ours == lsof)
        #expect(ours.count == 3)
        #expect(Set(ours.map(\.port)) == Set(printed))
        #expect(ours.contains(Entry(pid: child.pid, transport: .tcp, port: printed[0], address: "127.0.0.1")))
        #expect(ours.contains(Entry(pid: child.pid, transport: .tcp, port: printed[1], address: "::1")))
        #expect(ours.contains(Entry(pid: child.pid, transport: .udp, port: printed[2], address: "127.0.0.1")))
    }

    /// Other processes may open or close a port between the two reads: up to three tries.
    @Test func everyOwnListenerMatchesLsof() async throws {
        var last: (ours: Set<Entry>, lsof: Set<Entry>) = ([], [])
        for _ in 0..<3 {
            let ours = Set(await ports.current().map(Self.entry))
            let lsof = try Self.lsof()
            last = (ours, lsof)
            if ours == lsof { break }
            try await Task.sleep(for: .milliseconds(300))
        }
        #expect(last.ours == last.lsof, "only ours: \(last.ours.subtracting(last.lsof)); only lsof: \(last.lsof.subtracting(last.ours))")
    }

    @Test func endedListenerIsGone() async throws {
        let child = try Child.listener()
        _ = try child.waitForLines(3)
        let pid = child.pid
        child.end()

        #expect(await ports.current().allSatisfy { $0.pid != pid })
    }

    /// Wildcards print as `*` in lsof; ours are `0.0.0.0` and `::`.
    private static func entry(_ socket: ListeningSocket) -> Entry {
        let address = ["0.0.0.0", "::"].contains(socket.address) ? "*" : socket.address
        return Entry(pid: socket.pid, transport: socket.transport, port: socket.port, address: address)
    }

    static func lsof() throws -> Set<Entry> {
        let tcp = try run(["-nP", "-iTCP", "-sTCP:LISTEN", "-FpPn"])
        let udp = try run(["-nP", "-iUDP", "-FpPn"])
        return parse(tcp).union(parse(udp))
    }

    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/lsof")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// `-F pPn`: `p<pid>`, then per file `P<protocol>` and `n<address:port>`; a connected UDP socket has `->`.
    private static func parse(_ output: String) -> Set<Entry> {
        var entries: Set<Entry> = []
        var pid: Int32 = 0
        var transport = Transport.tcp
        for line in output.split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value) ?? 0
            case "P": transport = value == "UDP" ? .udp : .tcp
            case "n":
                guard !value.contains("->"), let colon = value.lastIndex(of: ":"),
                    let port = UInt16(value[value.index(after: colon)...])
                else { continue }
                let address = value[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                entries.insert(Entry(pid: pid, transport: transport, port: port, address: address))
            default: continue
            }
        }
        return entries
    }
}
