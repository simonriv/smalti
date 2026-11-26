/// F8.5 review 2: a confirmation that runs a repo's commands only takes a key pressed while it is shown. A held ↩
/// that chose "Abrir proyecto" in ⌘K auto-repeats into the card; those repeats never confirm it.
public enum ConfirmationKey {
    public static func confirms(isRepeat: Bool) -> Bool { !isRepeat }
}
