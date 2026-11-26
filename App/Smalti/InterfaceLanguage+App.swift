import Foundation
import SmaltiCore

/// F7.7: the interface's language, resolved once from the bundle's preferred localizations: the same choice AppKit
/// and Sparkle make (spec, spike), so menus, panels, Sparkle and Smalti's own texts always agree. Only the app reads
/// the bundle; the domain receives the language as a value.
extension InterfaceLanguage {
    static let current = InterfaceLanguage(preferredLocalizations: Bundle.main.preferredLocalizations)
}

/// A domain catalog with its two languages; `current` picks the interface's.
protocol Bilingual {
    static var spanish: Self { get }
    static var english: Self { get }
}

extension Bilingual {
    static var current: Self { InterfaceLanguage.current == .spanish ? spanish : english }
}

extension CommandTexts: Bilingual {}
extension MenuTexts: Bilingual {}
extension HelpTexts: Bilingual {}
extension IntegrationTexts: Bilingual {}
extension TimeTexts: Bilingual {}
extension ObservatoryCopy: Bilingual {}
extension TelemetryCopy: Bilingual {}
extension StatusTexts: Bilingual {}
extension GuardTexts: Bilingual {}
extension TerminalTexts: Bilingual {}
extension SessionTexts: Bilingual {}
extension SharedLayoutErrorTexts: Bilingual {}
extension ConfigTexts: Bilingual {}
extension ConfigTemplateTexts: Bilingual {}
extension PromptCopy: Bilingual {}
extension AppearanceCopy: Bilingual {}
extension WelcomeTexts: Bilingual {}
extension ProcessTexts: Bilingual {}
extension ProjectTexts: Bilingual {}
