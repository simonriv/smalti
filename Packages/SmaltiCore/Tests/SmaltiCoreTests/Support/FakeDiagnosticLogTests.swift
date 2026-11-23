import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("FakeDiagnosticLog")
struct FakeDiagnosticLogTests {
    @Test func meetsTheContract() async throws {
        try await DiagnosticLogContract.verify(
            FakeDiagnosticLog(),
            directory: FileManager.default.temporaryDirectory.appending(path: "smalti-fake-\(UUID())"))
    }
}
