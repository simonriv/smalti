import Darwin
import SmaltiCore

/// The terminal behind a file descriptor, from `TIOCGWINSZ`: its width in cells and the pixel size of one cell. Nil
/// when it is not a terminal, does not report pixels, or is tmux (which drops kitty graphics unless passthrough is set
/// up): then `smalti img` writes a plain list.
enum TerminalSize {
    static func metrics(of descriptor: Int32, environment: [String: String]) -> CellMetrics? {
        guard isatty(descriptor) == 1, environment["TMUX", default: ""].isEmpty else { return nil }
        var size = winsize()
        // Safe: `size` outlives the call and is exactly the `winsize` TIOCGWINSZ fills.
        guard withUnsafeMutablePointer(to: &size, { ioctl(descriptor, TIOCGWINSZ, $0) }) == 0,
            size.ws_col > 0, size.ws_row > 0, size.ws_xpixel > 0, size.ws_ypixel > 0
        else { return nil }
        var metrics = CellMetrics(
            columns: Int(size.ws_col), cellWidth: Double(size.ws_xpixel) / Double(size.ws_col),
            cellHeight: Double(size.ws_ypixel) / Double(size.ws_row))
        metrics.visibleRows = Int(size.ws_row)
        return metrics
    }
}
