/// Look settings the user can change; the named parameter object that carries appearance into `Theme.applying`. Defaults are the Obsidiana theme.
public struct AppearanceSettings: Equatable, Sendable {
    /// `nil`: the theme's own accent (spec F5). Only the TOML sets it; choosing a theme in the UI clears it.
    public var accent: RGBAColor?
    public var glassOpacity: Double
    public var blur: Double
    public var fontFamily: String
    public var fontSize: Double
    public var gap: Double
    public var radius: Double

    public init(
        accent: RGBAColor?, glassOpacity: Double, blur: Double, fontFamily: String, fontSize: Double, gap: Double,
        radius: Double
    ) {
        self.accent = accent
        self.glassOpacity = glassOpacity
        self.blur = blur
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.gap = gap
        self.radius = radius
    }

    /// F5, outside the initializer like `SmaltiConfig.observatory`: the theme, "Proteger legibilidad" and the ANSI
    /// edits of each theme.
    public var theme = ThemeID.obsidiana
    public var protectLegibility = true
    public var ansiOverrides: [ThemeID: ANSIOverrides] = [:]

    public static let maximumFontFamilyLength = 100

    /// A font name that fits in one quoted line of a config file: 1 to `maximumFontFamilyLength` characters, with no
    /// quote, backslash or control character that could close the quote or start a new line.
    public static func isValidFontFamily(_ name: String) -> Bool {
        (1...maximumFontFamilyLength).contains(name.count)
            && !name.unicodeScalars.contains(where: isForbiddenInFontFamily)
    }

    private static func isForbiddenInFontFamily(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\"" || scalar == "\\" || scalar.properties.generalCategory == .control
    }

    public static let obsidian = AppearanceSettings(
        accent: nil,
        glassOpacity: Theme.obsidian.window.background.alpha,
        blur: Theme.obsidian.window.blurRadius,
        fontFamily: Theme.obsidian.terminal.fontFamily,
        fontSize: Theme.obsidian.terminal.fontSize,
        gap: Theme.obsidian.panel.gap,
        radius: Theme.obsidian.panel.cornerRadius)
}

/// Everything configurable. A valid configuration is always complete: missing values take their default.
public struct SmaltiConfig: Equatable, Sendable {
    public var appearance: AppearanceSettings
    public var defaultLayout: LayoutID
    public var shell: TerminalCommand
    public var keys: Keymap
    /// Not in the initializer: every other table predates it, and the defaults are what nearly everyone wants.
    public var observatory = ObservatorySettings.standard
    /// `[input]` (F4); like `observatory`, outside the initializer.
    public var input = InputSettings.standard
    /// `[window]` (F4.5); like `observatory`, outside the initializer.
    public var window = WindowSettings.standard
    /// `[prompt]` (F5); like `observatory`, outside the initializer.
    public var prompt = PromptConfig.standard
    /// `[preview]` (F5.5); like `observatory`, outside the initializer.
    public var preview = PreviewSettings.standard
    /// `[extras]` (F7); like `observatory`, outside the initializer.
    public var extras = ExtrasSettings.standard

    public init(appearance: AppearanceSettings, defaultLayout: LayoutID, shell: TerminalCommand, keys: Keymap) {
        self.appearance = appearance
        self.defaultLayout = defaultLayout
        self.shell = shell
        self.keys = keys
    }

    public static let defaults = SmaltiConfig(
        appearance: .obsidian, defaultLayout: .dwindle, shell: .loginShell, keys: .standard)

    /// Shell precedence (spec R2): defaults < `[shell] command` < launch override. The override exists only so
    /// automated tests can run a shell without startup files; `nil` keeps the configured shell.
    public func withShell(overriddenBy override: TerminalCommand?) -> SmaltiConfig {
        guard let override else { return self }
        var resolved = self
        resolved.shell = override
        return resolved
    }
}
