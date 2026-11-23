import GhosttyKit
import SmaltiCore

extension GhosttySurfaceView {
    /// At the shell prompt by OSC 133: libghostty keeps the semantic state and `needs_confirm_quit` returns
    /// `!cursorIsAtPrompt()` with `confirm-close-surface = true` (also false on the alternate screen). A finished
    /// process also "needs no confirmation", so it is checked too. Costs about 0.4 µs (F4 spike).
    var isAtPrompt: Bool {
        guard let surface else { return false }
        return !ghostty_surface_process_exited(surface) && !ghostty_surface_needs_confirm_quit(surface)
    }

    /// The cursor's cell in points, origin at the view's top-left. `ime_point` gives the cell's horizontal center
    /// and bottom edge.
    var cursorCell: Rect? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        let scale = window?.backingScaleFactor ?? 2
        let width = Double(size.cell_width_px) / scale
        let height = Double(size.cell_height_px) / scale
        guard width > 0, height > 0 else { return nil }
        var x = 0.0
        var y = 0.0
        var imeWidth = 0.0
        var imeHeight = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &imeWidth, &imeHeight)
        return Rect(x: x - width / 2, y: y - height, width: width, height: height)
    }
}
