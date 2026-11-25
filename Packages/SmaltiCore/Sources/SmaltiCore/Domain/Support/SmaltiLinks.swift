import Foundation

/// F7.6: the pages of smalti.sh the app opens, in Spanish while the interface is (F7.7 makes them follow it).
public enum SmaltiLinks {
    public static let documentation = link("https://smalti.sh/es/docs")
    public static let support = link("https://smalti.sh/es#apoyar")
    static let newIssue = "https://github.com/simonriv/smalti/issues/new"

    private static func link(_ text: String) -> URL {
        guard let url = URL(string: text) else {
            // Unreachable: every argument is a constant, valid URL.
            preconditionFailure("invalid link \(text)")
        }
        return url
    }
}
