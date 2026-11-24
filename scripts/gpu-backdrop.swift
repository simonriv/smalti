import AppKit

// F5 C6 (issue #5): a full-screen window that hides the rest of the desktop while measuring the GPU, so another
// translucent app redrawing (a terminal streaming output) does not leak into the number. `moving` animates bars all
// the time (a video or a busy app behind the glass); `static` paints them once. Usage: gpu-backdrop static|moving
let isMoving = CommandLine.arguments.dropFirst().first == "moving"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.main else { exit(1) }
let frame = screen.frame
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .normal
let view = NSView(frame: frame)
view.wantsLayer = true
view.layer?.backgroundColor = NSColor.white.cgColor
let barCount = 12
for index in 0..<barCount {
    let bar = CALayer()
    let height = frame.height / CGFloat(barCount)
    bar.frame = CGRect(x: CGFloat(index) * 90, y: CGFloat(index) * height, width: 160, height: height * 0.85)
    bar.backgroundColor =
        NSColor(hue: CGFloat(index) / CGFloat(barCount), saturation: 0.8, brightness: 0.9, alpha: 1)
        .cgColor
    view.layer?.addSublayer(bar)
    guard isMoving else { continue }
    let move = CABasicAnimation(keyPath: "position.x")
    move.fromValue = 80
    move.toValue = frame.width - 80
    move.duration = 2 + Double(index) * 0.3
    move.autoreverses = true
    move.repeatCount = .infinity
    bar.add(move, forKey: "move")
}
window.contentView = view
window.orderFrontRegardless()
app.run()
