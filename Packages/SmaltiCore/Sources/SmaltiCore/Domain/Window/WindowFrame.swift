/// Where a window goes on screen. Frames here, and the ones saved in `WindowSnapshot`, are in AppKit's screen
/// coordinates (origin at the bottom-left of the main screen, y up), unlike the panes' layout rects.
public enum WindowFrame {
    /// Points of a saved frame that must stay on some screen, on each axis, for it to count as visible.
    static let minimumVisible = 100.0
    /// How far a new window steps down and right from the front one.
    public static let cascadeStep = 24.0

    /// A saved frame on the screen that shows most of it: kept when it is whole on it, else moved the least to be
    /// (shrunk first if larger). When no screen shows enough of it (a monitor was unplugged), it is centered on
    /// `main` with its size capped to it.
    public static func fitted(_ frame: Rect, screens: [Rect], main: Rect) -> Rect {
        let visible = screens.filter { isVisible(frame, on: $0) }
        guard let screen = visible.max(by: { overlap(frame, $0) < overlap(frame, $1) }) else {
            return centered(capped(frame.size, to: main), in: main)
        }
        return inside(Rect(origin: frame.origin, size: capped(frame.size, to: screen)), screen)
    }

    private static func overlap(_ frame: Rect, _ screen: Rect) -> Double {
        let width = min(frame.maxX, screen.maxX) - max(frame.minX, screen.minX)
        let height = min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY)
        return max(width, 0) * max(height, 0)
    }

    /// ⌘N: a window of `size` hanging one step below and right of the front one's top-left corner; past the visible
    /// screen it starts again at its top-left, and it never exceeds it.
    public static func cascaded(from front: Rect, size: Size, visible: Rect) -> Rect {
        let capped = capped(size, to: visible)
        let next = Rect(
            x: front.minX + cascadeStep, y: front.maxY - cascadeStep - capped.height, width: capped.width,
            height: capped.height)
        guard next.maxX > visible.maxX || next.minY < visible.minY else { return next }
        return Rect(
            x: visible.minX + cascadeStep, y: visible.maxY - cascadeStep - capped.height, width: capped.width,
            height: capped.height)
    }

    private static func isVisible(_ frame: Rect, on screen: Rect) -> Bool {
        let width = min(frame.maxX, screen.maxX) - max(frame.minX, screen.minX)
        let height = min(frame.maxY, screen.maxY) - max(frame.minY, screen.minY)
        return width >= minimumVisible && height >= minimumVisible
    }

    private static func capped(_ size: Size, to screen: Rect) -> Size {
        Size(width: min(size.width, screen.size.width), height: min(size.height, screen.size.height))
    }

    private static func centered(_ size: Size, in screen: Rect) -> Rect {
        Rect(
            x: screen.minX + (screen.size.width - size.width) / 2,
            y: screen.minY + (screen.size.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Moves `frame` the least needed to sit inside `screen`; it already fits by size. A frame already inside stays.
    private static func inside(_ frame: Rect, _ screen: Rect) -> Rect {
        let x = min(max(frame.minX, screen.minX), screen.maxX - frame.size.width)
        let y = min(max(frame.minY, screen.minY), screen.maxY - frame.size.height)
        return Rect(x: x, y: y, width: frame.size.width, height: frame.size.height)
    }
}
