/// Process names that mean "the pane is at its shell prompt". A login shell reports itself with a leading `-`.
public enum ShellNames {
    private static let shells: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "mksh", "tcsh", "csh", "nu", "xonsh", "elvish", "pwsh",
    ]

    public static func contains(_ name: String) -> Bool {
        shells.contains(name.hasPrefix("-") ? String(name.dropFirst()) : name)
    }
}
