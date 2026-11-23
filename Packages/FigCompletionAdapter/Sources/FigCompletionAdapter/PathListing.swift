import Foundation
import SmaltiCore

/// The entries for a path being typed (`src/ma`, `~/Do`, `Pro`): the folder part stays, the last part filters by
/// prefix. Folders end in `/`; hidden entries only appear when the typed part starts with `.`; a bare `~` is the
/// home folder. At most `PathListingLimits.maximum` entries, so a huge folder stays quick.
struct PathListing {
    let prefix: String
    let directory: String

    func entries(foldersOnly: Bool) -> [Suggestion] {
        let (folderPart, partial) = split(prefix == "~" ? "~/" : prefix)
        let folder = resolve(folderPart)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        else { return [] }
        let matching = names.sorted().filter { name in
            name.hasPrefix(partial) && (partial.hasPrefix(".") || !name.hasPrefix("."))
        }
        return matching.lazy.compactMap { name -> Suggestion? in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(
                atPath: folder.appending(path: name).path(percentEncoded: false), isDirectory: &isFolder)
            guard isFolder.boolValue || !foldersOnly else { return nil }
            return Suggestion(name: folderPart + name + (isFolder.boolValue ? "/" : ""))
        }.prefix(PathListingLimits.maximum).map { $0 }
    }

    private func split(_ typed: String) -> (folder: String, partial: String) {
        guard let slash = typed.lastIndex(of: "/") else { return ("", typed) }
        return (String(typed[...slash]), String(typed[typed.index(after: slash)...]))
    }

    private func resolve(_ folderPart: String) -> URL {
        if folderPart.hasPrefix("/") { return URL(filePath: folderPart) }
        if folderPart == "~/" || folderPart.hasPrefix("~/") {
            return URL(filePath: NSHomeDirectory()).appending(path: String(folderPart.dropFirst(2)))
        }
        return URL(filePath: directory).appending(path: folderPart)
    }
}

/// How many entries a path completion lists at most: a huge folder must not stall the menu.
public enum PathListingLimits {
    public static let maximum = 500
}
