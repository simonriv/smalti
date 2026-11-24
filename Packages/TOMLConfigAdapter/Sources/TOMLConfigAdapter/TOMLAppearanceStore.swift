import Foundation
import SmaltiCore

/// `AppearanceStore` on `theme.toml` (spec F5). It writes the whole file atomically; when the file changed on disk
/// since the configuration was loaded or last written, the hand edit is read first and the UI's changes are applied on
/// top of it. A symlinked file (dotfiles) is written through its link.
@MainActor
public final class TOMLAppearanceStore: AppearanceStore {
    private let file: URL
    /// The document the UI started from and the file's modification date then (load, reload or last write).
    private var baseline: (document: AppearanceDocument, date: Date?)?

    public init(file: URL) {
        self.file = file
    }

    /// Call with what was loaded from the files (startup, "Recargar configuración"), so the first save of a session
    /// keeps an edit made by hand afterwards (block 3 review, I5).
    public func remember(_ document: AppearanceDocument) {
        baseline = (document, modificationDate())
    }

    /// The file written: the link's target when `theme.toml` is a symlink.
    private var target: URL { file.resolvingSymlinksInPath() }
    private var path: String { target.path(percentEncoded: false) }

    @discardableResult
    public func save(_ document: AppearanceDocument) throws(ConfigError) -> AppearanceDocument {
        let merged = rebasedOnHandEdit(document)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(TOMLWriter.text(merged).utf8).write(to: target, options: .atomic)
        } catch {
            throw ConfigError(
                file: path, line: nil, key: nil, reason: "no se pudo escribir: \(error.localizedDescription)")
        }
        baseline = (merged, modificationDate())
        return merged
    }

    /// Keys missing from the edited file read as defaults, so deleting one by hand is respected (M8). A file that no
    /// longer parses is kept as `theme.toml.bak` and overwritten: "Recargar configuración" already showed its error.
    private func rebasedOnHandEdit(_ document: AppearanceDocument) -> AppearanceDocument {
        guard let baseline, modificationDate() != baseline.date,
            let text = try? String(contentsOf: target, encoding: .utf8)
        else { return document }
        guard let external = try? TOMLConfigParser.parseTheme(text, file: path, over: .defaults) else {
            backUp(text)
            return document
        }
        return document.rebased(onto: AppearanceDocument(config: external), from: baseline.document)
    }

    private func backUp(_ text: String) {
        let backup = target.deletingLastPathComponent().appending(path: target.lastPathComponent + ".bak")
        try? Data(text.utf8).write(to: backup, options: .atomic)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
