import AppKit
import SmaltiCore

extension RGBAColor {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha))
    }
}
