import AppKit
import SmaltiCore

/// The palette's 16×16 icons, drawn from the SVG paths of Paleta.dc.html (viewBox 0 0 16 16, y down).
enum CommandIcons {
    /// Side of the board's SVG viewBox; paths are written in its units.
    static let viewBoxSize = 16.0

    /// Icons the board defines; other commands keep the icon column empty so titles stay aligned.
    static func path(for command: CommandID) -> NSBezierPath? {
        switch command {
        case .layout(.dwindle): frame(with: [line(8.5, 2, 8.5, 14), line(8.5, 8, 14.5, 8)])
        case .layout(.columns): frame(with: [line(5.8, 2, 5.8, 14), line(10.2, 2, 10.2, 14)])
        case .layout(.master): frame(with: [line(1.5, 8.5, 14.5, 8.5), line(8, 8.5, 8, 14)])
        case .panesEqualize: equalize
        default: nil
        }
    }

    /// Magnifier of the search field.
    static var search: NSBezierPath {
        let path = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 9, height: 9))
        path.append(line(10.5, 10.5, 14, 14))
        return path
    }

    private static func frame(with strokes: [NSBezierPath]) -> NSBezierPath {
        let path = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2, width: 13, height: 12), xRadius: 2, yRadius: 2)
        strokes.forEach(path.append)
        return path
    }

    private static var equalize: NSBezierPath {
        let path = NSBezierPath()
        [
            line(2, 5, 14, 5), line(2, 11, 14, 11), polyline([(5, 2.5), (2, 5), (5, 7.5)]),
            polyline([(11, 8.5), (14, 11), (11, 13.5)]),
        ].forEach(path.append)
        return path
    }

    private static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> NSBezierPath {
        polyline([(x1, y1), (x2, y2)])
    }

    private static func polyline(_ points: [(Double, Double)]) -> NSBezierPath {
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let location = NSPoint(x: point.0, y: point.1)
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
        let scale = bounds.width / CommandIcons.viewBoxSize
        let scaled = path.copy() as? NSBezierPath ?? path
        scaled.transform(using: AffineTransform(scale: scale))
        scaled.lineWidth = lineWidth
        scaled.lineCapStyle = .round
        scaled.lineJoinStyle = .round
        color.setStroke()
        scaled.stroke()
    }
}
