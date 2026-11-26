/// F7.7 `[keyboard] option_as_meta`: whether ⌥ acts as Meta (Alt) in the terminal. `auto` leaves it to libghostty,
/// which turns it on only on the U.S. and U.S. International layouts; elsewhere ⌥ keeps typing characters.
public enum OptionAsMeta: String, CaseIterable, Sendable {
    case auto
    case never
    case left
    case right
    case always
}
