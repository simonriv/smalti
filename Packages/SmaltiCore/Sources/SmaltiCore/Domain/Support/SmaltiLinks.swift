import Foundation

/// The pages of smalti.sh the app opens, in the interface's language (F7.7): English at the root, Spanish under
/// `/es`, with each language's own anchors.
public enum SmaltiLinks {
    private static let site = "https://smalti.sh"

    public static func documentation(for language: InterfaceLanguage) -> URL {
        link(prefix(language) + "/docs")
    }

    public static func support(for language: InterfaceLanguage) -> URL {
        link(language == .spanish ? site + "/es#apoyar" : site + "/#support")
    }

    public static func privacy(for language: InterfaceLanguage) -> URL {
        link(prefix(language) + "/privacy")
    }

    public static func releaseNotes(version: String, for language: InterfaceLanguage) -> URL {
        link(prefix(language) + "/changelog#v" + version)
    }

    private static func prefix(_ language: InterfaceLanguage) -> String {
        language == .spanish ? site + "/es" : site
    }
    static let newIssue = "https://github.com/simonriv/smalti/issues/new"

    private static func link(_ text: String) -> URL {
        guard let url = URL(string: text) else {
            // Unreachable: every argument is a constant, valid URL.
            preconditionFailure("invalid link \(text)")
        }
        return url
    }
}
