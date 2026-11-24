import Foundation
import Testing

/// Spec F5.5 C13: only this adapter reads images (ImageIO), and the preview never logs, so it can never publish a path
/// or a file name.
@Suite("ImageIOAdapter guard")
struct ImageIOAdapterGuardTests {
    private static let skipped = ["/.build/", "/build/", "/.git/", "/vendor/", "/.superpowers/", "/Tests/", "UITests/"]
    /// The preview's own code: the domain, the use cases, the adapter, `smalti img` and the app's card.
    private static let previewCode = [
        "Packages/SmaltiCore/Sources/SmaltiCore/Domain/Preview/",
        "Packages/SmaltiCore/Sources/SmaltiCore/Application/Preview",
        "Packages/SmaltiCore/Sources/SmaltiCore/Application/ShowImageGrid.swift", "Packages/ImageIOAdapter/Sources/",
        "Packages/IPCAdapter/Sources/smalti/ImageCommand.swift", "App/Smalti/Preview/",
    ]
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func onlyThisAdapterImportsImageIO() {
        let importers = sources().filter { file in
            !relative(file).hasPrefix("Packages/ImageIOAdapter/") && lines(of: file).contains("import ImageIO")
        }

        #expect(importers.isEmpty, "import ImageIO: \(importers.map(relative))")
    }

    @Test func previewCodeNeverLogs() {
        let loggers = sources().filter { file in
            Self.previewCode.contains(where: relative(file).hasPrefix)
                && lines(of: file).contains { $0.contains("Logger(") || $0.contains("os_log(") }
        }

        #expect(loggers.isEmpty, "the preview logs in: \(loggers.map(relative))")
    }

    @Test func guardSeesThePreviewCode() {
        #expect(sources().filter { Self.previewCode.contains(where: relative($0).hasPrefix) }.count >= 10)
    }

    private func relative(_ file: URL) -> String {
        String(file.path(percentEncoded: false).dropFirst(root.path(percentEncoded: false).count))
    }

    private func lines(of file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private func sources() -> [URL] {
        ["App", "Packages"].flatMap { folder in
            let enumerator = FileManager.default.enumerator(
                at: root.appending(path: folder), includingPropertiesForKeys: nil)
            var found: [URL] = []
            while let url = enumerator?.nextObject() as? URL {
                let path = url.path(percentEncoded: false)
                guard url.pathExtension == "swift", !Self.skipped.contains(where: path.contains) else { continue }
                found.append(url)
            }
            return found
        }
    }
}
