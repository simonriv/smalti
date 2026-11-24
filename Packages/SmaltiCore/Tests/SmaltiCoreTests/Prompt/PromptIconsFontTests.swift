import Foundation
import SmaltiCore
import Testing

/// F5 T12: `SmaltiSymbols` has one glyph per `PromptIcon`, in the same order (scripts/fonts/icons.txt).
@Suite("PromptIcons and the font")
struct PromptIconsFontTests {
    private static let list = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts/fonts/icons.txt")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: list.path(percentEncoded: false))))
    func codepointsMatchFontOrder() throws {
        let names = try String(contentsOf: Self.list, encoding: .utf8).split(whereSeparator: \.isWhitespace).map(
            String.init)

        #expect(names == PromptIcon.allCases.map { "\($0)" })
    }
}
