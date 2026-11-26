/// F7.7: the language of the interface. The composition root resolves it once from the bundle's preferred
/// localizations (the same choice AppKit and Sparkle make) and hands it to everything that writes text.
public enum InterfaceLanguage: String, Sendable, CaseIterable {
    case english = "en"
    case spanish = "es"

    /// The first entry that is English or Spanish decides; any other language falls back to English, as the bundle does.
    public init(preferredLocalizations: [String]) {
        let decided = preferredLocalizations.lazy.compactMap { entry in
            Self.allCases.first { entry == $0.rawValue || entry.hasPrefix($0.rawValue + "-") }
        }.first
        self = decided ?? .english
    }
}
