import Foundation
import SmaltiCore

/// `AppearanceStore` on `theme.toml` (spec F5). It writes the whole file atomically; when the file changed on disk
/// since this store last wrote it, the hand edit is read first and the UI's changes are applied on top of it.
@MainActor
public final class TOMLAppearanceStore: AppearanceStore {
    private let file: URL
    /// What this store last wrote, and the file's modification date right after.
    private var written: (document: AppearanceDocument, date: Date?)?

    public init(file: URL) {
        self.file = file
    }

    private var path: String { file.path(percentEncoded: false) }

    public func save(_ document: AppearanceDocument) throws(ConfigError) {
        let merged = rebasedOnHandEdit(document)
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(TOMLWriter.text(merged).utf8).write(to: file, options: .atomic)
        } catch {
            throw ConfigError(
                file: path, line: nil, key: nil, reason: "no se pudo escribir: \(error.localizedDescription)")
        }
        written = (merged, modificationDate())
    }

    /// A file that does not parse is overwritten: "Recargar configuración" already showed its error.
    private func rebasedOnHandEdit(_ document: AppearanceDocument) -> AppearanceDocument {
        guard let written, modificationDate() != written.date,
            let text = try? String(contentsOf: file, encoding: .utf8),
            let external = try? TOMLConfigParser.parseTheme(
                text, file: path, over: written.document.applied(to: .defaults))
        else { return document }
        return document.rebased(onto: AppearanceDocument(config: external), from: written.document)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
