import Foundation

public enum FeedbackKind: Equatable, Sendable {
    case bug, idea
}

/// The GitHub issue a report opens, prefilled. Nothing is sent from the app: the user reads it and submits it.
public enum FeedbackReport {
    static let newIssue = "https://github.com/simonriv/smalti/issues/new"

    /// RFC 3986's unreserved characters: everything else in a value is percent-encoded (`&`, `#`, `+`, accents).
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func issueURL(kind: FeedbackKind, build: BuildInfo) -> URL {
        let query = [("labels", label(kind)), ("title", title(kind)), ("body", body(kind, build: build))]
            .map { name, value in name + "=" + encoded(value) }
            .joined(separator: "&")
        guard let url = URL(string: newIssue + "?" + query) else {
            // Unreachable: the base is a valid constant and every value is percent-encoded to unreserved characters.
            preconditionFailure("issue URL could not be built from \(newIssue)")
        }
        return url
    }

    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// "Fallo: " / "Idea: ", for the user to finish.
    private static func title(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: "Fallo: "
        case .idea: "Idea: "
        }
    }

    private static func label(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: "bug"
        case .idea: "idea"
        }
    }

    private static func body(_ kind: FeedbackKind, build: BuildInfo) -> String {
        let sections =
            switch kind {
            case .bug: "### Qué pasó\n\n\n### Qué esperabas\n\n\n### Pasos\n\n1. \n"
            case .idea: "### La idea\n\n\n### Para qué la usarías\n\n"
            }
        return sections + "\n---\n" + build.summary + "\n"
    }
}
