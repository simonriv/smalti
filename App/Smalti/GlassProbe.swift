import Foundation

/// Debug-only diagnostic for issue #5 (F5 T1): `-SmaltiGlassProbe <piece>` removes one piece of the glass so
/// `scripts/measure-gpu-idle.sh` can measure what each one costs at rest. Release builds always paint everything.
enum GlassProbe: String {
    case none
    /// The window content without its rounded mask (`masksToBounds`).
    case noMask
    /// The window without its shadow.
    case noShadow
    /// No background blur behind the window.
    case noBlur
    /// Panes without their rounded clip over the Metal surface.
    case noPaneMask
    /// An opaque window: no transparency to composite at all.
    case opaque

    static let current: GlassProbe = {
        #if DEBUG
            UserDefaults.standard.string(forKey: "SmaltiGlassProbe").flatMap(GlassProbe.init(rawValue:)) ?? .none
        #else
            .none
        #endif
    }()
}
