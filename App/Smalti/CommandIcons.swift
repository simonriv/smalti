import AppKit
import SmaltiCore

/// Palette icons as `NSBezierPath`, in the boards' 16×16 viewBox (y down). Command icons come from the domain
/// (`Command.icon`, declared by each layout); only the search magnifier, which is not a command, lives here.
enum CommandIcons {
    static func path(for icon: CommandIcon) -> NSBezierPath {
        let path = NSBezierPath()
        if let frame = icon.frame {
            path.append(NSBezierPath(roundedRect: NSRect(frame), xRadius: icon.frameRadius, yRadius: icon.frameRadius))
        }
        icon.strokes.forEach { path.append(polyline($0)) }
        return path
    }

    /// `circle cx=7 cy=7 r=4.5` and `M10.5 10.5L14 14` (Paleta.dc.html search field).
    static var search: NSBezierPath {
        let path = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 9, height: 9))
        path.append(polyline([Point(x: 10.5, y: 10.5), Point(x: 14, y: 14)]))
        return path
    }

    private static func polyline(_ points: [Point]) -> NSBezierPath {
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let location = NSPoint(x: point.x, y: point.y)
            if index == 0 { path.move(to: location) } else { path.line(to: location) }
        }
        return path
    }
}

/// Strokes one of `CommandIcons` in a flipped 16×16 box.
@MainActor
final class CommandIconView: NSView {
    private let path: NSBezierPath?
    private let lineWidth: Double
    var color: NSColor = .clear { didSet { needsDisplay = true } }

    init(_ path: NSBezierPath?, size: Double, lineWidth: Double) {
        self.path = path
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let path else { return }
        let scale = bounds.width / CommandIcon.viewBoxSize
        let scaled = path.copy() as? NSBezierPath ?? path
        scaled.transform(using: AffineTransform(scale: scale))
        scaled.lineWidth = lineWidth
        scaled.lineCapStyle = .round
        scaled.lineJoinStyle = .round
        color.setStroke()
        scaled.stroke()
    }
}
