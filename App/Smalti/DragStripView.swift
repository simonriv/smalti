import AppKit

/// Top strip of the window. Empty in F0; dragging it moves the window.
final class DragStripView: NSView {
    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.dragStrip")
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
