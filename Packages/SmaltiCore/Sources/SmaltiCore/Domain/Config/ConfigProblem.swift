/// F7.7: what is wrong with a configuration value, without words: the config adapters report it and
/// `ConfigTexts` writes it in the interface's language.
public enum ConfigProblem: Equatable, Sendable {
    case syntax
    case unknownTable
    case unknownKey
    case unreadableFile(detail: String)
    case noReadPermission
    case notUTF8
    case unwritable(detail: String)
    /// F7.6: the file is from a newer Smalti, so the app does not overwrite it.
    case newerNotOverwritten
    case expectedTable
    case expectedNumber
    case expectedText
    case expectedFlag
    case expectedTextList
    case expectedVersion
    case expectedIntegerBetween(Int, Int)
    case expectedNumberBetween(Double, Double)
    case notNegative
    case expectedPositiveInteger
    case missingKeys([String])
    case expectedANSIIndex
    case expectedColor
    case expectedFontName(maximumLength: Int)
    case expectedOneOf([String])
    case unknownTheme([String])
    case unknownLayout([String])
    case unknownModule(String)
    case repeatedModule(String)
    case expectedShellCommand
    case expectedCommandID
    case unknownCommand
    case repeatedShortcut(first: String)
    case invalidChord(KeyChordError)
    /// ⌥ without ⌘ or ⌃ is for typing characters (F1, R8).
    case reservedOption
}
