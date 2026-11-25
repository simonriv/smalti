import Foundation

public enum FeedbackKind: Equatable, Sendable {
    case bug, idea
}

/// The GitHub issue a report opens, prefilled. Nothing is sent from the app: the user reads it and submits it.
/// The GitHub issue a report opens: the public repo's issue form for its kind, with the title started and the build
/// filled in. Nothing is sent from the app: the user reads it and submits it (F4.5; forms since F7.6).
public enum FeedbackReport {
    /// The id of the form field that holds the build (`.github/ISSUE_TEMPLATE/*.yml`).
    public static let buildFieldID = "build"

    /// RFC 3986's unreserved characters: everything else in a value is percent-encoded (`&`, `#`, `+`, accents).
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func issueURL(kind: FeedbackKind, build: BuildInfo) -> URL {
        let query = [("template", template(kind)), ("title", title(kind)), (buildFieldID, build.summary)]
            .map { name, value in name + "=" + encoded(value) }
            .joined(separator: "&")
        guard let url = URL(string: SmaltiLinks.newIssue + "?" + query) else {
            // Unreachable: the base is a valid constant and every value is percent-encoded to unreserved characters.
            preconditionFailure("issue URL could not be built from \(SmaltiLinks.newIssue)")
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

    private static func template(_ kind: FeedbackKind) -> String {
        switch kind {
        case .bug: "bug.yml"
        case .idea: "idea.yml"
        }
    }
}
