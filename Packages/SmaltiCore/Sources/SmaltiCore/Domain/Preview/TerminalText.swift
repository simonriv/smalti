/// Text that came from outside (a file name) on its way to a terminal: control characters (C0, DEL, C1) become `?` so
/// a name never moves the cursor or clears the screen, and its width counts terminal cells, wide characters as two.
public enum TerminalText {
    public static func sanitized(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { isControl($0) ? "?" : $0 }))
    }

    public static func width(_ text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    static func width(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        return isWide(scalar.value) ? 2 : 1
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
    }

    /// East Asian wide and fullwidth blocks and the emoji planes, the cells terminals give two columns.
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1F64F,
        0x1F900...0x1F9FF, 0x20000...0x3FFFD,
    ]

    private static func isWide(_ value: UInt32) -> Bool {
        wideRanges.contains { $0.contains(value) }
    }
}
