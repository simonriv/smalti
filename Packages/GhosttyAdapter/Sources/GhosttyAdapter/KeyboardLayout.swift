import Carbon

/// Identifier of the active keyboard input source (e.g. "com.apple.keylayout.LatinAmerican").
enum KeyboardLayout {
    static var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        // Safe: kTISPropertyInputSourceID is documented to be a CFString owned by the source.
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
}
