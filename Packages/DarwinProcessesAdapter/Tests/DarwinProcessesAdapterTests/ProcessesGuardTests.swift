import Foundation
import Testing

/// C9 of F8: listing every process, reading sockets, changing priorities and sending a stop signal live only in this
/// adapter. `kill` keeps older, narrower uses elsewhere: a liveness probe with signal 0 and the PTY test helper's
/// variable signal. String literals and comments are not code (the texts say "SIGKILL").
@Suite("Darwin processes adapter guard")
struct ProcessesGuardTests {
    private static let symbols = [
        "proc_pidfdinfo", "PROC_PIDLISTFDS", "setpriority(", "KERN_PROC_ALL", "SIGKILL", "SIGTERM",
    ]
    private static let adapterPackage = "DarwinProcessesAdapter"

    private let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // DarwinProcessesAdapterTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // DarwinProcessesAdapter
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    @Test func onlyThisAdapterSignalsAndReadsSockets() throws {
        let packages = try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appending(path: "Packages").path(percentEncoded: false))
        let roots =
            packages.filter { $0 != Self.adapterPackage }.map {
                repositoryRoot.appending(path: "Packages/\($0)/Sources")
            }
            + [repositoryRoot.appending(path: "App/Smalti")]

        // Test support (the PTY helper ends what its tests start) is not product code.
        let product = try roots.flatMap(swiftFiles).filter { !$0.path(percentEncoded: false).contains("TestSupport/") }
        let hits = try product.flatMap(Self.hits)

        #expect(hits.isEmpty, "\(hits.joined(separator: "\n"))")
    }

    @Test func theAdapterUsesEachOfThem() throws {
        let sources = repositoryRoot.appending(path: "Packages/\(Self.adapterPackage)/Sources")
        let code = try swiftFiles(in: sources).flatMap(Self.codeLines).joined(separator: "\n")

        for symbol in Self.symbols { #expect(code.contains(symbol), "\(symbol) not used by the adapter") }
    }

    @Test func aLiteralSignalElsewhereIsCaught() {
        #expect(Self.isForbidden("        kill(pid, 9)"))
        #expect(Self.isForbidden("kill(process.pid, SIGHUP)"))
        #expect(!Self.isForbidden("kill(pid, 0) == 0"))
        #expect(!Self.isForbidden("for pid in processes(naming: root) { kill(pid, signal) }"))
        #expect(!Self.isForbidden("let body = \"Forcing it (SIGKILL) ends it\""))
        #expect(!Self.isForbidden("/// only the confirmation sends SIGKILL"))
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)),
            let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private static func hits(in file: URL) throws -> [String] {
        let lines = try String(contentsOf: file, encoding: .utf8).split(
            separator: "\n", omittingEmptySubsequences: false)
        return lines.enumerated().compactMap { index, line in
            isForbidden(String(line)) ? "\(file.lastPathComponent):\(index + 1): \(line)" : nil
        }
    }

    private static func codeLines(in file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { code(of: String($0)) }
    }

    static func isForbidden(_ line: String) -> Bool {
        let code = code(of: line)
        // `kill(pid, SIGHUP)` or `kill(pid, 9)`: a literal signal other than 0.
        let literalSignal = #/\bkill\([^,()]+,\s*(SIG[A-Z]+|[1-9][0-9]*)\s*\)/#
        return symbols.contains(where: code.contains) || code.contains(literalSignal)
    }

    /// The line without its comment and without what is inside string literals.
    private static func code(of line: String) -> String {
        let beforeComment = line.components(separatedBy: "//").first ?? ""
        return beforeComment.components(separatedBy: "\"").enumerated().filter { $0.offset.isMultiple(of: 2) }
            .map(\.element).joined(separator: "\"\"")
    }
}
