import Foundation
import SmaltiCore

/// The entries for a path being typed (`src/ma`, `~/Do`, `Pro`): the folder part stays, the last part filters by
/// prefix. Folders end in `/`; hidden entries only appear when the typed part starts with `.`.
struct PathListing {
    let prefix: String
    let directory: String

    func entries(foldersOnly: Bool) -> [Suggestion] {
        let (folderPart, partial) = split()
        let folder = resolve(folderPart)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        else { return [] }
        return names.sorted().compactMap { name in
            guard name.hasPrefix(partial), partial.hasPrefix(".") || !name.hasPrefix(".") else { return nil }
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(
                atPath: folder.appending(path: name).path(percentEncoded: false), isDirectory: &isFolder)
            guard isFolder.boolValue || !foldersOnly else { return nil }
            return Suggestion(name: folderPart + name + (isFolder.boolValue ? "/" : ""))
        }
    }

    private func split() -> (folder: String, partial: String) {
        guard let slash = prefix.lastIndex(of: "/") else { return ("", prefix) }
        return (String(prefix[...slash]), String(prefix[prefix.index(after: slash)...]))
    }

    private func resolve(_ folderPart: String) -> URL {
        if folderPart.hasPrefix("/") { return URL(filePath: folderPart) }
        if folderPart == "~/" || folderPart.hasPrefix("~/") {
            return URL(filePath: NSHomeDirectory()).appending(path: String(folderPart.dropFirst(2)))
        }
        return URL(filePath: directory).appending(path: folderPart)
    }
}
