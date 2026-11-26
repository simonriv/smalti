import CryptoKit
import Foundation
import SmaltiCore

/// `ProjectFiles` on disk (F8.5): `<root>/.smalti/layout.json`, read once with its SHA-256 and validated as a project
/// file; written atomically with the JSON of shared layouts (F7).
public final class FileProjectFiles: ProjectFiles {
    static let folderName = ".smalti"
    static let fileName = "layout.json"

    public init() {}

    private func file(at root: String) -> URL {
        URL(filePath: root).appending(path: Self.folderName).appending(path: Self.fileName)
    }

    public func hasLayout(in directory: String) -> Bool {
        FileManager.default.fileExists(atPath: file(at: directory).path(percentEncoded: false))
    }

    public func isRepositoryRoot(_ directory: String) -> Bool {
        FileManager.default.fileExists(
            atPath: URL(filePath: directory).appending(path: ".git").path(percentEncoded: false))
    }

    public func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Checks the size before reading: a file over the limit is refused without loading it.
    public func layout(at root: String) throws(ProjectFileError) -> ProjectLayoutFile {
        let path = file(at: root).path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { throw .missing(root: root) }
        let data: Data
        do {
            let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0
            guard size <= SharedLayout.maximumBytes else { throw ProjectFileError.invalid(.tooLarge(bytes: size)) }
            data = try Data(contentsOf: URL(filePath: path))
        } catch let error as ProjectFileError {
            throw error
        } catch {
            throw .unreadable(root: root, reason: error.localizedDescription)
        }
        let layout: SharedLayout
        do { layout = try SharedLayoutJSON.decoded(data) } catch { throw Self.translated(error, root: root) }
        do { _ = try layout.validatedAsProject() } catch { throw .invalid(error) }
        return ProjectLayoutFile(layout: layout, fingerprint: Self.fingerprint(of: data))
    }

    public func write(_ layout: SharedLayout, to root: String) throws(ProjectFileError) -> String {
        let target = file(at: root)
        do {
            let data = try SharedLayoutJSON.encoded(layout)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return Self.fingerprint(of: data)
        } catch {
            throw .unwritable(path: target.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }

    static func fingerprint(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func translated(_ error: LayoutFileError, root: String) -> ProjectFileError {
        switch error {
        case .invalid(let reason): .invalid(reason)
        case .unreadable(_, let reason): .unreadable(root: root, reason: reason)
        case .unwritable(let path, let reason): .unwritable(path: path, reason: reason)
        }
    }
}
