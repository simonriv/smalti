/// Where a window goes on screen, in AppKit's screen coordinates (origin bottom-left, y up).
public enum WindowFrame {
    /// Points of a saved frame that must stay on some screen, on each axis, for it to count as visible.
    static let minimumVisible = 100.0
    /// How far a new window steps down and right from the front one.
    public static let cascadeStep = 24.0

    /// A saved frame, kept if it is still visible on some screen; shrunk into that screen if it is larger; or, when
    /// no screen shows enough of it (a monitor was unplugged), centered on `main` with its size capped to it.
    public static func fitted(_ frame: Rect, screens: [Rect], main: Rect) -> Rect {
        guard let screen = screens.first(where: { isVisible(frame, on: $0) }) else {
            return centered(capped(frame.size, to: main), in: main)
        }
        guard frame.size.width > screen.size.width || frame.size.height > screen.size.height else { return frame }
        return inside(Rect(origin: frame.origin, size: capped(frame.size, to: screen)), screen)
    }

    public static func cascaded(from front: Rect, step: Double = cascadeStep) -> Rect {
        Rect(x: front.minX + step, y: front.minY - step, width: front.size.width, height: front.size.height)
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

    /// Moves `frame` the least needed to sit inside `screen`; it already fits by size.
    private static func inside(_ frame: Rect, _ screen: Rect) -> Rect {
        let x = min(max(frame.minX, screen.minX), screen.maxX - frame.size.width)
        let y = min(max(frame.minY, screen.minY), screen.maxY - frame.size.height)
        return Rect(x: x, y: y, width: frame.size.width, height: frame.size.height)
    }
}
