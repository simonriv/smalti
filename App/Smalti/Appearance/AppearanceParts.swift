import AppKit
import SmaltiCore

/// A clickable, focusable box (theme card, ANSI swatch, segment): click or Space runs `action`; accessibility sees
/// a button whose value says whether it is selected.
@MainActor
class PanelButtonView: NSView {
    var action: (() -> Void)?

    init(identifier: String, label: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    /// A drag on it never moves the window (transparent views do by default).
    override var mouseDownCanMoveWindow: Bool { false }

    /// Its labels are part of it: a click anywhere on it is its click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) { action?() }
    override func accessibilityPerformPress() -> Bool {
        action?()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else { return super.keyDown(with: event) }
        action?()
    }

    func showSelected(_ isSelected: Bool) {
        setAccessibilityValue(isSelected ? "seleccionado" : nil)
    }
}

/// Theme card: a preview with three bars over the theme's background, and its name (`Apariencia.dc.html`).
@MainActor
final class ThemeCardView: PanelButtonView {
    private let preview = NSView()
    private let bars = [NSView(), NSView(), NSView()]
    private let name = NSTextField(labelWithString: "")

    init(id: ThemeID) {
        super.init(identifier: "smalti.appearance.theme.\(id.rawValue)", label: id.displayName(.spanish /* T9 */))
        preview.wantsLayer = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)
        for bar in bars {
            bar.wantsLayer = true
            bar.translatesAutoresizingMaskIntoConstraints = false
            preview.addSubview(bar)
        }
    }

    func render(_ id: ThemeID, isSelected: Bool, theme: Theme) {
        let tokens = theme.appearancePanel
        layer?.cornerRadius = tokens.cardCornerRadius
        layer?.borderWidth = isSelected ? tokens.cardSelectedBorderWidth : tokens.cardBorderWidth
        layer?.borderColor = (isSelected ? tokens.selectedCardBorder : tokens.cardBorder).nsColor.cgColor
        layer?.backgroundColor = isSelected ? tokens.selectedCardBackground.nsColor.cgColor : nil
        let swatch = id.swatch
        preview.layer?.cornerRadius = tokens.previewCornerRadius
        preview.layer?.backgroundColor = swatch.background.nsColor.cgColor
        for (bar, color) in zip(bars, [swatch.accent, swatch.text, swatch.green]) {
            bar.layer?.cornerRadius = tokens.previewBarHeight / 2
            bar.layer?.backgroundColor = color.nsColor.cgColor
        }
        name.attributedStringValue = title(id, isSelected: isSelected, theme: theme)
        showSelected(isSelected)
        if constraints.isEmpty { layoutParts(tokens) }
    }

    private func title(_ id: ThemeID, isSelected: Bool, theme: Theme) -> NSAttributedString {
        let tokens = theme.appearancePanel
        let text = NSMutableAttributedString(
            string: id.displayName(.spanish /* T9 */),
            attributes: [
                .font: theme.interfaceFont(size: tokens.rowFontSize, weight: 500),
                .foregroundColor: (isSelected ? tokens.title : tokens.text).nsColor,
            ])
        if let note = id.cardNote {
            text.append(
                NSAttributedString(
                    string: " " + note,
                    attributes: [
                        .font: theme.interfaceFont(size: tokens.rowFontSize),
                        .foregroundColor: tokens.secondary.nsColor,
                    ]))
        }
        return text
    }

    private func layoutParts(_ tokens: AppearancePanelTokens) {
        let padding = tokens.cardPadding
        var constraints = [
            preview.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            preview.heightAnchor.constraint(equalToConstant: tokens.previewHeight),
            name.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: tokens.cardInnerGap),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            name.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ]
        var previous: NSView?
        for (bar, fraction) in zip(bars, tokens.previewBarWidths) {
            constraints += [
                bar.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: padding),
                bar.widthAnchor.constraint(equalTo: preview.widthAnchor, multiplier: fraction),
                bar.heightAnchor.constraint(equalToConstant: tokens.previewBarHeight),
                bar.topAnchor.constraint(
                    equalTo: previous?.bottomAnchor ?? preview.topAnchor,
                    constant: previous == nil ? padding : tokens.previewBarGap),
            ]
            previous = bar
        }
        NSLayoutConstraint.activate(constraints)
    }
}

/// One of the 16 ANSI swatches; its accessibility value is the color it shows.
@MainActor
final class SwatchView: PanelButtonView {
    init(index: Int) {
        super.init(identifier: "smalti.appearance.ansi.\(index)", label: "ANSI \(index)")
    }

    func render(_ color: RGBAColor, tokens: AppearancePanelTokens) {
        layer?.cornerRadius = tokens.swatchCornerRadius
        layer?.backgroundColor = color.nsColor.cgColor
        setAccessibilityValue(color.hexString)
        if constraints.isEmpty {
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: tokens.swatchSize),
                heightAnchor.constraint(equalToConstant: tokens.swatchSize),
            ])
        }
    }
}

/// One choice of a segmented row ("Ocultos", "Al pasar el cursor", "Visibles").
@MainActor
final class SegmentView: PanelButtonView {
    private let label = NSTextField(labelWithString: "")

    init(identifier: String, title: String, inset: Double) {
        super.init(identifier: identifier, label: title)
        label.stringValue = title
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: inset),
        ])
    }

    /// A choice that cannot be taken (Nerd Font without one installed): dimmed, and disabled for accessibility.
    var isEnabledChoice = true {
        didSet {
            alphaValue = isEnabledChoice ? 1 : Self.disabledAlpha
            setAccessibilityEnabled(isEnabledChoice)
        }
    }

    private static let disabledAlpha = 0.4

    func render(isSelected: Bool, theme: Theme) {
        let tokens = theme.appearancePanel
        layer?.cornerRadius = tokens.segmentCornerRadius
        layer?.backgroundColor = isSelected ? tokens.selectedSegment.nsColor.cgColor : nil
        label.font = theme.interfaceFont(size: tokens.segmentFontSize, weight: 500)
        label.textColor = (isSelected ? tokens.title : tokens.muted).nsColor
        showSelected(isSelected)
    }
}

/// Glass and blur: whole steps with the arrows, 10 with ⇧ (spec F5, "Teclado").
@MainActor
final class PanelSlider: NSSlider {
    static let step = 1.0
    static let largeStep = 10.0
    var onChange: ((Double) -> Void)?

    init(identifier: String, range: ClosedRange<Double>) {
        super.init(frame: .zero)
        minValue = range.lowerBound
        maxValue = range.upperBound
        numberOfTickMarks = Int(range.upperBound - range.lowerBound) + 1
        allowsTickMarkValuesOnly = true
        tickMarkPosition = .below
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(changed)
        setAccessibilityIdentifier(identifier)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// Clicked, it takes the keyboard so the arrows move it (also without full keyboard access).
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    /// Tick marks are only for snapping: none drawn, as on the board.
    override func rectOfTickMark(at index: Int) -> NSRect { .zero }

    override func keyDown(with event: NSEvent) {
        let step = event.modifierFlags.contains(.shift) ? Self.largeStep : Self.step
        switch event.specialKey {
        case .rightArrow?, .upArrow?: move(by: step)
        case .leftArrow?, .downArrow?: move(by: -step)
        default: super.keyDown(with: event)
        }
    }

    private func move(by step: Double) {
        doubleValue = min(max(doubleValue + step, minValue), maxValue)
        changed()
    }

    @objc private func changed() {
        onChange?(doubleValue.rounded())
    }
}

/// A value with a stepper (font size, gap, radius): the text as on the board, the arrows to change it.
@MainActor
final class StepperValueView: NSStackView {
    let stepper = NSStepper()
    let value = NSTextField(labelWithString: "")
    var onChange: ((Double) -> Void)?

    init(identifier: String, range: ClosedRange<Double>, gap: Double) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = gap
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = 1
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = #selector(stepped)
        stepper.setAccessibilityIdentifier(identifier)
        addArrangedSubview(value)
        addArrangedSubview(stepper)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    func render(_ number: Double, text: String, theme: Theme) {
        stepper.doubleValue = number
        value.stringValue = text
        value.font = theme.interfaceFont(size: theme.appearancePanel.rowFontSize)
        value.textColor = theme.appearancePanel.text.nsColor
    }

    @objc private func stepped() {
        onChange?(stepper.doubleValue)
    }
}
