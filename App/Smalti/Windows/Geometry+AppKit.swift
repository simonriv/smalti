import AppKit
import SmaltiCore

/// Window frames cross between AppKit and the domain in screen coordinates (origin bottom-left), unchanged. The other
/// way, `NSRect(_: Rect)`, lives next to the pane grid.
extension Rect {
    init(_ rect: NSRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
