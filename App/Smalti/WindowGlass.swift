import AppKit

/// Background blur behind the window with an exact radius (design: 0–48 px).
/// Uses the private CoreGraphics call Ghostty uses; falls back to a system material if it is unavailable.
enum WindowGlass {
    private typealias SetBlurRadius = @convention(c) (UInt32, Int, Int32) -> Int32
    private typealias MainConnectionID = @convention(c) () -> UInt32

    @MainActor
    static func apply(blurRadius: Double, to window: NSWindow) {
        guard
            let setBlur = symbol("CGSSetWindowBackgroundBlurRadius", as: SetBlurRadius.self),
            let connection = symbol("CGSMainConnectionID", as: MainConnectionID.self),
            setBlur(connection(), window.windowNumber, Int32(blurRadius.rounded())) == 0
        else {
            addSystemMaterial(to: window)
            return
        }
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        // RTLD_DEFAULT: CoreGraphics is already loaded by AppKit.
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)  // Safe: the symbol has this C signature on macOS 10.x–27.
    }

    @MainActor
    private static func addSystemMaterial(to window: NSWindow) {
        guard let content = window.contentView else { return }
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(material, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: content.topAnchor),
            material.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            material.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            material.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }
}
