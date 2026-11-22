import AppKit
import SmaltiCore

extension RGBAColor {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha))
    }
}

extension Theme {
    /// Inter at `size` and `weight` (CSS 400/500/600). Falls back to the system font while Inter is not installed.
    @MainActor
    func interfaceFont(size: Double, weight: Int = 400) -> NSFont {
        Self.font(family: text.interfaceFontFamily, size: size, weight: weight)
            ?? .systemFont(ofSize: size, weight: Self.systemWeight(weight))
    }

    @MainActor
    var kbdFont: NSFont {
        Self.font(family: kbd.fontFamily, size: kbd.fontSize, weight: 400)
            ?? .monospacedSystemFont(ofSize: kbd.fontSize, weight: .regular)
    }

    /// Font lookups by descriptor are slow and the chrome re-renders often; fonts never change at run time.
    @MainActor private static var fonts: [FontKey: NSFont?] = [:]

    private struct FontKey: Hashable {
        let family: String
        let size: Double
        let weight: Int
    }

    @MainActor
    private static func font(family: String, size: Double, weight: Int) -> NSFont? {
        let key = FontKey(family: family, size: size, weight: weight)
        if let cached = fonts[key] { return cached }
        let font = lookUp(family: family, size: size, weight: weight)
        fonts[key] = font
        return font
    }

    private static func lookUp(family: String, size: Double, weight: Int) -> NSFont? {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family, .traits: [NSFontDescriptor.TraitKey.weight: systemWeight(weight).rawValue],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == family else { return nil }
        return font
    }

    private static func systemWeight(_ cssWeight: Int) -> NSFont.Weight {
        switch cssWeight {
        case ..<450: .regular
        case ..<550: .medium
        default: .semibold
        }
    }
}
