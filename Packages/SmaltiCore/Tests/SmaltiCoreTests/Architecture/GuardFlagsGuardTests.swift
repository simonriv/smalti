import Foundation
import SmaltiCore
import Testing

/// F7.5 review 2 (M8): the guard's test flags (`-SmaltiProjectPermissionsRoot`, `-SmaltiApprovalTimeoutSeconds`) are
/// read only in Debug builds, so a persisted default can never redirect the daily Smalti.
@Suite("Guard flags guard")
struct GuardFlagsGuardTests {
    private static let composition = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Smalti/AppComposition.swift")

    private static var isInRepository: Bool {
        FileManager.default.fileExists(atPath: composition.path(percentEncoded: false))
    }

    @Test(.enabled(if: isInRepository))
    func guardFlagsAreReadOnlyInDebug() throws {
        let lines = try String(contentsOf: Self.composition, encoding: .utf8).split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        let reads = lines.indices.filter { lines[$0].contains("LaunchSettings.guardArgumentKeys") }

        #expect(!reads.isEmpty)
        for index in reads { #expect(index > 0 && lines[index - 1] == "#if DEBUG", "line \(index + 1)") }
    }
}
