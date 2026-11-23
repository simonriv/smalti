import AppKit
import SmaltiCore

/// The observatory's building blocks: a card (radius 11 on the dark glass) and the board's labels.
@MainActor
final class ObservatoryCard: NSView {
    let content = NSStackView()

    /// `holdsContent: false` gives the bare card (the table fills it edge to edge, with no padded stack).
    init(theme: Theme, spacing: Double, holdsContent: Bool = true) {
        super.init(frame: .zero)
        let tokens = theme.observatory
        wantsLayer = true
        layer?.cornerRadius = tokens.cardRadius
        layer?.backgroundColor = tokens.cardBackground.nsColor.cgColor
        layer?.borderColor = tokens.cardBorder.nsColor.cgColor
        layer?.borderWidth = theme.chrome.hairlineWidth
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = spacing
        guard holdsContent else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: tokens.cardPaddingVertical),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.cardPaddingHorizontal),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.cardPaddingHorizontal),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -tokens.cardPaddingVertical),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Pins this card to `host`'s edges: the observatory's panels hold a card instead of being one.
    func fill(_ host: NSView) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor), bottomAnchor.constraint(equalTo: host.bottomAnchor),
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
    }
}

/// Labels as the board styles them.
@MainActor
enum ObservatoryText {
    static func label(_ text: String, size: Double, color: RGBAColor, theme: Theme, weight: Int = 400) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = theme.interfaceFont(size: size, weight: weight)
        field.textColor = color.nsColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func number(_ text: String, size: Double, color: RGBAColor, theme: Theme) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = theme.monospacedFont(size: size)
        field.textColor = color.nsColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    /// The board's section labels are uppercase with tracking; the text stays as written in the code (readable
    /// identifiers and accessibility), and only its display is uppercased.
    static func caption(_ text: String, theme: Theme) -> NSTextField {
        let tokens = theme.observatory
        let font = theme.interfaceFont(size: tokens.labelSize)
        let field = NSTextField(
            labelWithAttributedString: NSAttributedString(
                string: text.uppercased(),
                attributes: [
                    .font: font, .foregroundColor: theme.text.secondary.nsColor,
                    .kern: tokens.labelTracking * tokens.labelSize,
                ]))
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func setText(_ field: NSTextField, _ text: String) {
        field.stringValue = text
        field.setAccessibilityValue(text)
    }
}

/// A polyline over the last samples, scaled to its box (the board's 300 × 34 curves and 300 × 110 chart).
@MainActor
final class Sparkline: NSView {
    struct Style {
        let line: RGBAColor
        let width: Double
        var fill: RGBAColor?
        var peak: (radius: Double, label: String, font: NSFont, color: RGBAColor)?
        var grid: [(fraction: Double, color: RGBAColor)] = []
    }

    private var values: [Double] = []
    private var maximum: Double?
    private var style: Style?

    override var isFlipped: Bool { true }

    /// `maximum` fixes the top of the scale (100 for percentages); nil scales to the highest value.
    func show(_ values: [Double], maximum: Double?, style: Style) {
        self.values = values
        self.maximum = maximum
        self.style = style
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let style else { return }
        for line in style.grid {
            line.color.nsColor.setStroke()
            let y = bounds.height * line.fraction
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: bounds.width, y: y))
            path.stroke()
        }
        let points = scaled()
        guard points.count > 1 else { return }
        if let fill = style.fill {
            let area = NSBezierPath()
            area.move(to: NSPoint(x: points[0].x, y: bounds.height))
            points.forEach(area.line(to:))
            area.line(to: NSPoint(x: points[points.count - 1].x, y: bounds.height))
            area.close()
            fill.nsColor.setFill()
            area.fill()
        }
        let curve = NSBezierPath()
        curve.lineWidth = style.width
        curve.move(to: points[0])
        points.dropFirst().forEach(curve.line(to:))
        style.line.nsColor.setStroke()
        curve.stroke()
        drawPeak(points, style: style)
    }

    private func scaled() -> [NSPoint] {
        let top = max(maximum ?? (values.max() ?? 0), 1)
        let step = values.count > 1 ? bounds.width / Double(values.count - 1) : 0
        let inset = (style?.peak?.radius ?? 0) + (style?.width ?? 0)
        let height = bounds.height - inset
        return values.enumerated().map { index, value in
            NSPoint(x: Double(index) * step, y: inset + height * (1 - min(value, top) / top))
        }
    }

    private func drawPeak(_ points: [NSPoint], style: Style) {
        guard let peak = style.peak, let index = values.indices.max(by: { values[$0] < values[$1] }) else { return }
        let point = points[index]
        style.line.nsColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: point.x - peak.radius, y: point.y - peak.radius, width: peak.radius * 2, height: peak.radius * 2)
        ).fill()
        let text = NSAttributedString(
            string: peak.label, attributes: [.font: peak.font, .foregroundColor: peak.color.nsColor])
        let size = text.size()
        let x = min(point.x + peak.radius * 2, bounds.width - size.width)
        text.draw(at: NSPoint(x: max(0, x), y: max(0, point.y - size.height - peak.radius)))
    }
}
