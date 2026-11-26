import Foundation
import Testing

/// C9 of F8: listing every process, reading sockets and changing priorities live only in this adapter. (`kill`
/// has older, narrower uses: a liveness probe with signal 0 and the PTY test helper.)
@Suite("Darwin processes adapter guard")
struct ProcessesGuardTests {
    private static let symbols = [
        "proc_pidfdinfo", "PROC_PIDLISTFDS", "setpriority(", "KERN_PROC_ALL", ", SIGKILL)", ", SIGTERM)",
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

        let hits = try roots.flatMap(swiftFiles).flatMap(Self.hits)

        #expect(hits.isEmpty, "\(hits.joined(separator: "\n"))")
    }

    @Test func theAdapterUsesThem() throws {
        let sources = repositoryRoot.appending(path: "Packages/\(Self.adapterPackage)/Sources")

        #expect(try !swiftFiles(in: sources).flatMap(Self.hits).isEmpty)
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
            let code = String(line).components(separatedBy: "//").first ?? ""
            return symbols.contains(where: code.contains) ? "\(file.lastPathComponent):\(index + 1): \(line)" : nil
        }
    }
}
