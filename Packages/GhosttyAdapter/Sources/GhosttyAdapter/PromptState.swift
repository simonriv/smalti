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

    /// Runs a libghostty binding action (F4.5: copy, search, scroll…). Main thread, like every surface call. False
    /// when there is no surface or libghostty did not run it (an unknown name, a search with nothing active).
    @discardableResult
    func bind(_ action: String) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    /// What is on screen as plain text; empty without a surface.
    var visibleText: String {
        surface.flatMap(ScrollbackExporter.visibleText) ?? ""
    }

    /// Presses Return in the terminal, as the keyboard would (F4: ⌘↩ in the history palette runs the line).
    func pressReturn() {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.keycode = 0x24
        key.mods = GHOSTTY_MODS_NONE
        key.consumed_mods = GHOSTTY_MODS_NONE
        for action in [GHOSTTY_ACTION_PRESS, GHOSTTY_ACTION_RELEASE] {
            key.action = action
            _ = ghostty_surface_key(surface, key)
        }
    }

    /// The cursor's cell in points, origin at the view's top-left.
    var cursorCell: Rect? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        var point = CursorCell.ImePoint(x: 0, y: 0, height: 0)
        var width = 0.0
        ghostty_surface_ime_point(surface, &point.x, &point.y, &width, &point.height)
        return CursorCell.rect(
            ime: point,
            cellPixels: CursorCell.Pixels(width: Double(size.cell_width_px), height: Double(size.cell_height_px)))
    }
}

/// `ime_point` gives the cursor cell's horizontal center, its bottom edge and its height, in points. The width
/// follows from the cell's pixel ratio, so no screen scale is assumed (a 1x display, a view without a window).
enum CursorCell {
    struct ImePoint {
        var x: Double
        var y: Double
        var height: Double
    }

    struct Pixels {
        let width: Double
        let height: Double
    }

    static func rect(ime: ImePoint, cellPixels: Pixels) -> Rect? {
        guard ime.height > 0, cellPixels.width > 0, cellPixels.height > 0 else { return nil }
        let width = ime.height * cellPixels.width / cellPixels.height
        return Rect(x: ime.x - width / 2, y: ime.y - ime.height, width: width, height: ime.height)
    }
}
