import Foundation

/// How dropped files become text for the terminal: each path escaped for a POSIX shell, joined by spaces, as Ghostty
/// does. A program that enables bracketed paste (Claude Code) receives it as a paste and attaches an image path.
enum DroppedFiles {
    /// Ghostty's set (Ghostty.Shell.swift) plus `~`.
    private static let escaped = Set(#" ()'"&;|<>*?$`\!#~{}[]"# + "\t")

    static func pasteText(for urls: [URL]) -> String {
        urls.map { escape($0.path(percentEncoded: false)) }.joined(separator: " ")
    }

    private static func escape(_ path: String) -> String {
        path.reduce(into: "") { text, character in
            if escaped.contains(character) { text.append("\\") }
            text.append(character)
        }
    }
}
