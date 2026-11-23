import Carbon.HIToolbox

/// The virtual key codes F4's overlays read (Carbon's `kVK_*`, layout independent).
enum KeyCode {
    static let upArrow = UInt16(kVK_UpArrow)
    static let downArrow = UInt16(kVK_DownArrow)
    static let tab = UInt16(kVK_Tab)
    static let returnKey = UInt16(kVK_Return)
    static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    static let escape = UInt16(kVK_Escape)
    static let delete = UInt16(kVK_Delete)
}

/// How often the Tab menu and the ⌃R palette check that their pane is still at its prompt (spec: a command that
/// starts closes them within a quarter of a second).
enum PromptWatch {
    static let interval: TimeInterval = 0.25
}
