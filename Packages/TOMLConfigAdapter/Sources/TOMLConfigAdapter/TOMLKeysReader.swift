import SmaltiCore

/// `[keys]`: chord → command id, or `"none"` to unbind. Every error names the chord as the user wrote it and its
/// line, including the ones `Keymap.overriding` raises (R8).
enum KeysReader {
    private static let unbindKeyword = "none"
    private static let valueReason = "se esperaba un id de comando o \"none\""
    private static let knownCommands = Set(CommandID.allStandard)

    static func read(_ section: TOMLSection, over keymap: Keymap) throws(ConfigError) -> Keymap {
        var bindings: [KeyChord: CommandID?] = [:]
        var writtenChords: [KeyChord: String] = [:]
        for text in section.keysInFileOrder {
            let chord = try chord(text, in: section)
            if let first = writtenChords[chord] {
                throw section.error(at: text, "atajo repetido; ya aparece como \(first)")
            }
            writtenChords[chord] = text
            bindings[chord] = try command(at: text, in: section)
        }
        return try apply(bindings, to: keymap, writtenAs: writtenChords, in: section)
    }

    private static func chord(_ text: String, in section: TOMLSection) throws(ConfigError) -> KeyChord {
        do {
            return try KeyChord.parse(text)
        } catch {
            throw section.error(at: text, reason(for: error))
        }
    }

    private static func command(at key: String, in section: TOMLSection) throws(ConfigError) -> CommandID? {
        let text = try section.text(key, reason: valueReason) ?? unbindKeyword
        if text == unbindKeyword { return nil }
        let command = CommandID(rawValue: text)
        guard knownCommands.contains(command) else {
            throw section.error(at: key, "comando desconocido; \(valueReason)")
        }
        return command
    }

    /// `Keymap.overriding` reports the chord by its display (`⌥K`); this puts back the user's text and its line.
    private static func apply(
        _ bindings: [KeyChord: CommandID?], to keymap: Keymap, writtenAs texts: [KeyChord: String],
        in section: TOMLSection
    ) throws(ConfigError) -> Keymap {
        do {
            return try keymap.overriding(bindings)
        } catch {
            guard let text = texts.first(where: { $0.key.display == error.key })?.value else { throw error }
            throw section.error(at: text, error.reason)
        }
    }

    private static func reason(for error: KeyChordError) -> String {
        switch error {
        case .missingModifier: "falta un modificador (⌘, ⌃ o ⌥)"
        case .duplicateModifier(let name): "modificador repetido: \(name)"
        case .unknownModifier(let name): "modificador desconocido: \(name)"
        case .unknownKey(let key): "tecla desconocida: \(key)"
        case .missingKey: "falta la tecla; el + se escribe plus"
        }
    }
}
