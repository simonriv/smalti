import Foundation
import SmaltiCore

/// F7.7: the language the CLI writes in. The app exports `SMALTI_LANGUAGE` (`en`, `es`) to every pane, so a hook
/// run by an agent there answers in the app's language; without it (or with another value) the system decides.
enum CLILanguage {
    static let variable = "SMALTI_LANGUAGE"

    static func resolve(environment: [String: String], preferred: [String]) -> InterfaceLanguage {
        if let value = environment[variable], let language = InterfaceLanguage(rawValue: value) { return language }
        return InterfaceLanguage(preferredLocalizations: preferred)
    }

    static func resolve(environment: [String: String]) -> InterfaceLanguage {
        resolve(environment: environment, preferred: Locale.preferredLanguages)
    }
}

extension InterfaceLanguage {
    var guardTexts: GuardTexts { self == .spanish ? .spanish : .english }
    var terminalTexts: TerminalTexts { self == .spanish ? .spanish : .english }
}
