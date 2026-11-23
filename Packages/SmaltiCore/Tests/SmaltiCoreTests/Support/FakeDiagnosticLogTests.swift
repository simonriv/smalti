import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("FakeDiagnosticLog")
struct FakeDiagnosticLogTests {
    @Test func meetsTheContract() throws {
        try DiagnosticLogContract.verify(
            FakeDiagnosticLog(),
            directory: FileManager.default.temporaryDirectory.appending(path: "smalti-fake-\(UUID())"))
    }
}
