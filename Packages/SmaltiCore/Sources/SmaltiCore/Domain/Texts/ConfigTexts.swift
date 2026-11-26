/// F7.7: the configuration's words: problems in `config.toml` and `theme.toml`, warnings, and the comments of the
/// files Smalti writes.
public struct ConfigTexts: Sendable, Equatable {
    public let syntax: String
    public let unknownTable: String
    public let unknownKey: String
    public let unreadableFile: TextTemplate
    public let noReadPermission: String
    public let notUTF8: String
    public let unwritable: TextTemplate
    public let newerNotOverwritten: String
    public let expectedTable: String
    public let expectedNumber: String
    public let expectedText: String
    public let expectedFlag: String
    public let expectedTextList: String
    public let expectedVersion: String
    public let expectedIntegerBetween: TextTemplate
    public let expectedNumberBetween: TextTemplate
    public let notNegative: String
    public let expectedPositiveInteger: String
    public let missingKeys: TextTemplate
    public let expectedANSIIndex: String
    public let expectedColor: String
    public let expectedFontName: TextTemplate
    public let expectedOneOf: TextTemplate
    public let unknownTheme: TextTemplate
    public let unknownLayout: TextTemplate
    public let unknownModule: TextTemplate
    public let repeatedModule: TextTemplate
    public let expectedShellCommand: String
    public let expectedCommandID: String
    public let unknownCommand: String
    public let repeatedShortcut: TextTemplate
    public let unknownModifier: TextTemplate
    public let unknownChordKey: TextTemplate
    public let duplicateModifier: TextTemplate
    public let missingModifier: String
    public let missingChordKey: String
    public let shiftOnSymbol: String
    public let reservedOption: String
    /// "a, b o c".
    public let lastOr: String
    public let decimalSeparator: String
    public let duplicatedKeys: TextTemplate
    public let newerFormat: TextTemplate
    public let themeFileHeader: String
    public let accentComment: String
    public let ansiComment: String
    public let starshipHeader: String
    public let template: ConfigTemplateTexts

    public static let spanish = ConfigTexts(
        syntax: "sintaxis TOML no válida", unknownTable: "tabla desconocida", unknownKey: "clave desconocida",
        unreadableFile: "no se pudo leer el archivo: {detail}",
        noReadPermission: "no se pudo leer el archivo: sin permiso de lectura", notUTF8: "el archivo no está en UTF-8",
        unwritable: "no se pudo escribir: {detail}",
        newerNotOverwritten: "es de una versión más nueva de Smalti: no se sobrescribe",
        expectedTable: "se esperaba una tabla", expectedNumber: "se esperaba un número",
        expectedText: "se esperaba un texto", expectedFlag: "se esperaba true o false",
        expectedTextList: "se esperaba una lista de textos",
        expectedVersion: "se esperaba un entero mayor o igual que 1",
        expectedIntegerBetween: "se esperaba un número entero entre {low} y {high}",
        expectedNumberBetween: "se esperaba un número entre {low} y {high}", notNegative: "debe ser ≥ 0",
        expectedPositiveInteger: "se esperaba un número entero mayor que 0", missingKeys: "faltan claves: {keys}",
        expectedANSIIndex: "se esperaba un índice ANSI de 0 a 15", expectedColor: "se esperaba un color #rrggbb",
        expectedFontName: "se esperaba un nombre de 1 a {maximum} caracteres sin comillas, \\ ni caracteres de control",
        expectedOneOf: "se esperaba {values}", unknownTheme: "tema desconocido; se esperaba {values}",
        unknownLayout: "layout desconocido; se esperaba {values}", unknownModule: "módulo desconocido: {name}",
        repeatedModule: "módulo repetido: {name}", expectedShellCommand: "se esperaba un comando o \"login\"",
        expectedCommandID: "se esperaba un id de comando o \"none\"",
        unknownCommand: "comando desconocido; se esperaba un id de comando o \"none\"",
        repeatedShortcut: "atajo repetido; ya aparece como {first}", unknownModifier: "modificador desconocido: {name}",
        unknownChordKey: "tecla desconocida: {key}", duplicateModifier: "modificador repetido: {name}",
        missingModifier: "falta un modificador (⌘, ⌃ o ⌥)", missingChordKey: "falta la tecla; el + se escribe plus",
        shiftOnSymbol: "⇧ no cuenta con números ni símbolos: escribe el carácter (cmd+? en vez de shift+cmd+/)",
        reservedOption: "⌥ sin ⌘ ni ⌃ queda reservado para escribir", lastOr: " o ", decimalSeparator: ",",
        duplicatedKeys: "theme.toml manda sobre config.toml en: {keys}",
        newerFormat: "{file} es de una versión más nueva de Smalti ({version}): se ignoran {keys}",
        themeFileHeader:
            "Lo escribe Smalti (Apariencia y Estudio de prompt). Puedes editarlo a mano: la app lo lee al recargar y lo reescribe entero al guardar.",
        accentComment: "sin él, el del tema", ansiComment: "solo los colores cambiados, 0–15",
        starshipHeader: "Generado por Smalti (Estudio de prompt).", template: .spanish)

    public static let english = ConfigTexts(
        syntax: "invalid TOML syntax", unknownTable: "unknown table", unknownKey: "unknown key",
        unreadableFile: "the file couldn’t be read: {detail}",
        noReadPermission: "the file couldn’t be read: no read permission", notUTF8: "the file isn’t UTF-8",
        unwritable: "couldn’t write: {detail}",
        newerNotOverwritten: "it’s from a newer Smalti: it isn’t overwritten", expectedTable: "expected a table",
        expectedNumber: "expected a number", expectedText: "expected a text", expectedFlag: "expected true or false",
        expectedTextList: "expected a list of texts", expectedVersion: "expected an integer of at least 1",
        expectedIntegerBetween: "expected an integer between {low} and {high}",
        expectedNumberBetween: "expected a number between {low} and {high}", notNegative: "must be ≥ 0",
        expectedPositiveInteger: "expected an integer greater than 0", missingKeys: "missing keys: {keys}",
        expectedANSIIndex: "expected an ANSI index from 0 to 15", expectedColor: "expected a #rrggbb color",
        expectedFontName: "expected a name of 1 to {maximum} characters without quotes, \\ or control characters",
        expectedOneOf: "expected {values}", unknownTheme: "unknown theme; expected {values}",
        unknownLayout: "unknown layout; expected {values}", unknownModule: "unknown module: {name}",
        repeatedModule: "repeated module: {name}", expectedShellCommand: "expected a command or \"login\"",
        expectedCommandID: "expected a command id or \"none\"",
        unknownCommand: "unknown command; expected a command id or \"none\"",
        repeatedShortcut: "repeated shortcut; it already appears as {first}",
        unknownModifier: "unknown modifier: {name}",
        unknownChordKey: "unknown key: {key}", duplicateModifier: "repeated modifier: {name}",
        missingModifier: "a modifier is missing (⌘, ⌃ or ⌥)", missingChordKey: "the key is missing; write + as plus",
        shiftOnSymbol: "⇧ doesn’t count with numbers or symbols: write the character (cmd+? instead of shift+cmd+/)",
        reservedOption: "⌥ without ⌘ or ⌃ is reserved for typing", lastOr: " or ", decimalSeparator: ".",
        duplicatedKeys: "theme.toml overrides config.toml for: {keys}",
        newerFormat: "{file} is from a newer Smalti ({version}): ignoring {keys}",
        themeFileHeader:
            "Written by Smalti (Appearance and Prompt Studio). You can edit it by hand: the app reads it on reload and rewrites it whole on save.",
        accentComment: "without it, the theme’s", ansiComment: "only the changed colors, 0–15",
        starshipHeader: "Generated by Smalti (Prompt Studio).", template: .english)

    /// The problem as one phrase. One exhaustive switch: a new `ConfigProblem` does not compile without its words.
    public func describe(_ problem: ConfigProblem) -> String {
        switch problem {
        case .syntax: syntax
        case .unknownTable: unknownTable
        case .unknownKey: unknownKey
        case .unreadableFile(let detail): unreadableFile(["detail": detail])
        case .noReadPermission: noReadPermission
        case .notUTF8: notUTF8
        case .unwritable(let detail): unwritable(["detail": detail])
        case .newerNotOverwritten: newerNotOverwritten
        case .expectedTable: expectedTable
        case .expectedNumber: expectedNumber
        case .expectedText: expectedText
        case .expectedFlag: expectedFlag
        case .expectedTextList: expectedTextList
        case .expectedVersion: expectedVersion
        case .expectedIntegerBetween(let low, let high):
            expectedIntegerBetween(["low": String(low), "high": String(high)])
        case .expectedNumberBetween(let low, let high):
            expectedNumberBetween(["low": number(low), "high": number(high)])
        case .notNegative: notNegative
        case .expectedPositiveInteger: expectedPositiveInteger
        case .missingKeys(let keys): missingKeys(["keys": keys.joined(separator: ", ")])
        case .expectedANSIIndex: expectedANSIIndex
        case .expectedColor: expectedColor
        case .expectedFontName(let maximum): expectedFontName(["maximum": String(maximum)])
        case .expectedOneOf(let values): expectedOneOf(["values": list(values)])
        case .unknownTheme(let values): unknownTheme(["values": list(values)])
        case .unknownLayout(let values): unknownLayout(["values": list(values)])
        case .unknownModule(let name): unknownModule(["name": name])
        case .repeatedModule(let name): repeatedModule(["name": name])
        case .expectedShellCommand: expectedShellCommand
        case .expectedCommandID: expectedCommandID
        case .unknownCommand: unknownCommand
        case .repeatedShortcut(let first): repeatedShortcut(["first": first])
        case .invalidChord(let error): describe(error)
        case .reservedOption: reservedOption
        }
    }

    private func describe(_ error: KeyChordError) -> String {
        switch error {
        case .unknownModifier(let name): unknownModifier(["name": name])
        case .unknownKey(let key): unknownChordKey(["key": key])
        case .duplicateModifier(let name): duplicateModifier(["name": name])
        case .missingModifier: missingModifier
        case .missingKey: missingChordKey
        case .shiftOnSymbol: shiftOnSymbol
        }
    }

    /// "a, b o c" / "a, b or c".
    private func list(_ values: [String]) -> String {
        guard let last = values.last, values.count > 1 else { return values.joined() }
        return values.dropLast().joined(separator: ", ") + lastOr + last
    }

    /// `0,3` / `0.3`; whole numbers without decimals.
    private func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(value).replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

/// The comments of the `config.toml` that ⌘, creates (`ConfigTemplate`), one string per comment line.
public struct ConfigTemplateTexts: Sendable, Equatable {
    public let header: [String]
    public let afterSave: String
    public let format: String
    public let layouts: String
    public let shell: String
    public let keyboard: String
    public let confirmClose: String
    public let preview: String
    public let observatory: [String]
    public let exampleModel: String
    public let keys: [String]

    public static let spanish = ConfigTemplateTexts(
        header: [
            "Configuración de Smalti. Quita el # de una línea para cambiar su valor; lo que no escribas conserva el valor por defecto."
        ],
        afterSave: "Después de guardar: ⌘K → \"Recargar configuración\".",
        format: "Formato del archivo: no lo cambies.",
        layouts: "Layouts: dwindle, columns, master.",
        shell: "\"login\" abre tu shell de inicio de sesión; también vale una orden, por ejemplo \"/bin/zsh\".",
        keyboard: "⌥ como Meta: auto (según la distribución del teclado), never, left, right o always.",
        confirmClose:
            "Preguntar antes de cerrar un panel, un workspace o una ventana, o de salir, con procesos en marcha.",
        preview: "Miniatura al pasar el cursor sobre un nombre de imagen; ⌘Y la abre en Quick Look.",
        observatory: [
            "Precios en dólares por millón de tokens y ventana de contexto; un modelo que Smalti no conoce necesita",
            "todas las claves. Por ejemplo:",
        ],
        exampleModel: "mi-modelo",
        keys: [
            "Un atajo por línea, del atajo al id del comando (la ayuda, ⌘?, muestra el id de cada acción al filtrar):",
            "Los atajos que escribas para un comando reemplazan los suyos por defecto; dos líneas para el mismo",
            "comando le dan dos atajos. \"none\" suelta un atajo.",
        ])

    public static let english = ConfigTemplateTexts(
        header: [
            "Smalti’s configuration. Remove the # from a line to change its value; what you don’t write keeps its default."
        ],
        afterSave: "After saving: ⌘K → \"Reload Configuration\".", format: "File format: don’t change it.",
        layouts: "Layouts: dwindle, columns, master.",
        shell: "\"login\" opens your login shell; a command works too, for example \"/bin/zsh\".",
        keyboard: "⌥ as Meta: auto (by keyboard layout), never, left, right or always.",
        confirmClose: "Ask before closing a pane, a workspace or a window, or quitting, with processes running.",
        preview: "Thumbnail when the pointer rests on an image name; ⌘Y opens it in Quick Look.",
        observatory: [
            "Prices in dollars per million tokens and context window; a model Smalti doesn’t know needs every",
            "key. For example:",
        ],
        exampleModel: "my-model",
        keys: [
            "One shortcut per line, from the shortcut to the command id (the help, ⌘?, shows each action’s id when filtering):",
            "The shortcuts you write for a command replace its default ones; two lines for the same command give",
            "it two shortcuts. \"none\" unbinds a shortcut.",
        ])
}
