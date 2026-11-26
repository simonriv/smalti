import SmaltiCore

/// `[keys]`: chord → command id, or `"none"` to unbind. Every error names the chord as the user wrote it and its
/// line, including the ones `Keymap.overriding` raises (R8).
enum TOMLKeysReader {
    private static let unbindKeyword = "none"
    private static let knownCommands = Set(CommandID.allStandard)

    static func read(_ section: TOMLSection, over keymap: Keymap) throws(ConfigError) -> Keymap {
        var bindings: [(chord: KeyChord, command: CommandID?)] = []
        var writtenChords: [KeyChord: String] = [:]
        for text in section.keysInFileOrder {
            let chord = try chord(text, in: section)
            if let first = writtenChords[chord] {
                throw section.error(at: text, .repeatedShortcut(first: first))
            }
            try validate(chord, writtenAs: text, in: section)
            writtenChords[chord] = text
            switch try binding(at: text, in: section) {
            case .command(let command): bindings.append((chord, command))
            case .unbound: bindings.append((chord, nil))
            case .skipped: continue
            }
        }
        return try apply(bindings, to: keymap, writtenAs: writtenChords, in: section)
    }

    private static func chord(_ text: String, in section: TOMLSection) throws(ConfigError) -> KeyChord {
        do {
            return try KeyChord.parse(text)
        } catch {
            throw section.error(at: text, .invalidChord(error))
        }
    }

    /// Checked here, in file order, so the first offending chord is the one reported.
    private static func validate(_ chord: KeyChord, writtenAs text: String, in section: TOMLSection)
        throws(ConfigError)
    {
        do {
            try Keymap.validate(chord)
        } catch {
            throw section.error(at: text, error.problem)
        }
    }

    private enum Binding {
        case command(CommandID)
        case unbound
        /// A newer file names a command this build does not have (F7.6).
        case skipped
    }

    private static func binding(at key: String, in section: TOMLSection) throws(ConfigError) -> Binding {
        let text = try section.text(key, reason: .expectedCommandID) ?? unbindKeyword
        if text == unbindKeyword { return .unbound }
        let command = CommandID(rawValue: text)
        guard knownCommands.contains(command) else {
            try section.skipUnknownValue(
                text, at: key, else: section.error(at: key, .unknownCommand))
            return .skipped
        }
        return .command(command)
    }

    /// `Keymap.overriding` reports the chord by its display (`⌥K`); this puts back the user's text and its line.
    private static func apply(
        _ bindings: [(chord: KeyChord, command: CommandID?)], to keymap: Keymap, writtenAs texts: [KeyChord: String],
        in section: TOMLSection
    ) throws(ConfigError) -> Keymap {
        do {
            return try keymap.overriding(ordered: bindings)
        } catch {
            guard let text = texts.first(where: { $0.key.display == error.key })?.value else { throw error }
            throw section.error(at: text, error.problem)
        }
    }
}
