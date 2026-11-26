import AppKit
import SmaltiCore

/// What the panel shows: the document being edited, what it paints, and where it is saved.
struct AppearancePanelState {
    let document: AppearanceDocument
    let applied: AppliedTheme
    let savedIn: String
}

/// The edits the panel's controls make; the controller turns them into `ChangeAppearance` calls.
enum AppearanceEdit {
    case theme(ThemeID)
    case glassOpacity(Double)
    case blur(Double)
    case protectLegibility(Bool)
    case pickANSI(Int)
    case buttons(WindowButtons)
    case fontFamily(String)
    case fontSize(Double)
    case gap(Double)
    case radius(Double)
}

/// The 440 px aside of `Apariencia.dc.html`. Built once; `render` refreshes every control from the state.
@MainActor
final class AppearancePanelView: NSView {
    var onEdit: ((AppearanceEdit) -> Void)?
    var onClose: (() -> Void)?

    private let title = NSTextField(labelWithString: "Apariencia")
    private let savedIn = NSTextField(labelWithString: "")
    private let labels = ["Tema", "Vidrio", "Paleta ANSI", "Botones de ventana"].map {
        NSTextField(labelWithString: $0)
    }
    private let cards = ThemeID.allCases.map { ThemeCardView(id: $0) }
    private let opacityTitle = NSTextField(labelWithString: "Opacidad del fondo")
    private let opacityValue = NSTextField(labelWithString: "")
    private let opacity = PanelSlider(
        identifier: "smalti.appearance.opacity",
        range: AppearancePanelView.percent(AppearanceSettings.glassOpacityRange))
    private let blurTitle = NSTextField(labelWithString: "Desenfoque")
    private let blurValue = NSTextField(labelWithString: "")
    private let blur = PanelSlider(identifier: "smalti.appearance.blur", range: AppearanceSettings.blurRange)
    private let legibilityTitle = NSTextField(labelWithString: "Proteger legibilidad")
    private let legibilityNote = NSTextField(
        labelWithString: "Sube la opacidad bajo el texto si el contraste cae de 4.5:1")
    private let legibility = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let swatches = (0..<16).map { SwatchView(index: $0) }
    private let adjusted = NSTextField(labelWithString: "")
    private let segmentContainer = NSView()
    private let segments: [(WindowButtons, SegmentView)] = [
        (.hidden, "Ocultos"), (.hover, "Al pasar el cursor"), (.visible, "Visibles"),
    ].map { mode, title in
        (
            mode,
            SegmentView(
                identifier: "smalti.appearance.buttons.\(mode.rawValue)", title: title,
                inset: Theme.obsidian.appearancePanel.segmentLabelInset)
        )
    }
    private let footerLabels = ["Fuente", "Espacio", "Radio"].map { NSTextField(labelWithString: $0) }
    private let fontFamily = NSPopUpButton()
    private let fontSize = StepperValueView(
        identifier: "smalti.appearance.fontSize", range: AppearanceSettings.fontSizeRange,
        gap: Theme.obsidian.appearancePanel.stepperGap)
    private let gap = StepperValueView(
        identifier: "smalti.appearance.gap", range: AppearanceSettings.gapRange,
        gap: Theme.obsidian.appearancePanel.stepperGap)
    private let radius = StepperValueView(
        identifier: "smalti.appearance.radius", range: AppearanceSettings.radiusRange,
        gap: Theme.obsidian.appearancePanel.stepperGap)
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.appearance")
        savedIn.setAccessibilityIdentifier("smalti.appearance.path")
        adjusted.setAccessibilityIdentifier("smalti.appearance.adjusted")
        legibility.setAccessibilityIdentifier("smalti.appearance.legibility")
        fontFamily.setAccessibilityIdentifier("smalti.appearance.fontFamily")
        connectControls()
        layoutPanel()
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    /// The first control the keyboard lands on.
    var firstControl: NSView { cards[0] }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    func render(_ state: AppearancePanelState) {
        theme = state.applied.theme
        let tokens = theme.appearancePanel
        let appearance = state.document.appearance
        layer?.backgroundColor = tokens.background(protectedAt: state.applied.opacities.chrome).nsColor.cgColor
        layer?.borderColor = tokens.border.nsColor.cgColor
        paintTexts(tokens)
        savedIn.stringValue = state.savedIn
        for (card, id) in zip(cards, ThemeID.allCases) {
            card.render(id, isSelected: id == appearance.theme, theme: theme)
        }
        opacity.doubleValue = (appearance.glassOpacity * 100).rounded()
        opacityValue.stringValue = AppearanceTexts.opacity(
            chosen: appearance.glassOpacity, underText: state.applied.opacities.panel, copy: .current)
        blur.doubleValue = appearance.blur
        blurValue.stringValue = AppearanceTexts.blur(appearance.blur)
        legibility.state = appearance.protectLegibility ? .on : .off
        let palette = ANSIPalette(
            base: ThemeCatalog.theme(appearance.theme).terminal.palette,
            overrides: appearance.ansiOverrides[appearance.theme] ?? .none)
        for (swatch, color) in zip(swatches, palette.colors) { swatch.render(color, tokens: tokens) }
        adjusted.stringValue =
            AppearanceTexts.adjusted(state.applied.adjustedColorCount, copy: .current) ?? ""
        adjusted.isHidden = state.applied.adjustedColorCount == 0
        for (mode, segment) in segments { segment.render(isSelected: mode == state.document.buttons, theme: theme) }
        segmentContainer.layer?.backgroundColor = tokens.segmentContainer.nsColor.cgColor
        segmentContainer.layer?.borderColor = tokens.segmentContainerBorder.nsColor.cgColor
        renderFont(appearance)
        gap.render(appearance.gap, text: AppearanceTexts.gap(appearance.gap), theme: theme)
        radius.render(appearance.radius, text: AppearanceTexts.radius(appearance.radius), theme: theme)
    }

    // MARK: - Controls

    private func connectControls() {
        for (card, id) in zip(cards, ThemeID.allCases) { card.action = { [weak self] in self?.onEdit?(.theme(id)) } }
        opacity.onChange = { [weak self] value in self?.onEdit?(.glassOpacity(value / 100)) }
        blur.onChange = { [weak self] value in self?.onEdit?(.blur(value)) }
        legibility.target = self
        legibility.action = #selector(toggledLegibility)
        for (index, swatch) in swatches.enumerated() {
            swatch.action = { [weak self] in self?.onEdit?(.pickANSI(index)) }
        }
        for (mode, segment) in segments { segment.action = { [weak self] in self?.onEdit?(.buttons(mode)) } }
        fontFamily.target = self
        fontFamily.action = #selector(choseFontFamily)
        fontFamily.isBordered = false
        fontSize.onChange = { [weak self] value in self?.onEdit?(.fontSize(value)) }
        gap.onChange = { [weak self] value in self?.onEdit?(.gap(value)) }
        radius.onChange = { [weak self] value in self?.onEdit?(.radius(value)) }
    }

    @objc private func toggledLegibility() {
        onEdit?(.protectLegibility(legibility.state == .on))
    }

    @objc private func choseFontFamily() {
        guard let family = fontFamily.titleOfSelectedItem else { return }
        onEdit?(.fontFamily(family))
    }

    private func renderFont(_ appearance: AppearanceSettings) {
        let families = Self.monospacedFamilies(including: appearance.fontFamily)
        if fontFamily.itemTitles != families {
            fontFamily.removeAllItems()
            fontFamily.addItems(withTitles: families)
        }
        fontFamily.selectItem(withTitle: appearance.fontFamily)
        fontFamily.font = theme.interfaceFont(size: theme.appearancePanel.rowFontSize)
        fontSize.render(
            appearance.fontSize,
            text: AppearanceTexts.font(family: "", size: appearance.fontSize).trimmingCharacters(in: .whitespaces),
            theme: theme)
    }

    /// The installed fixed-pitch families, plus the configured one if it is not installed (it still shows).
    private static func monospacedFamilies(including current: String) -> [String] {
        let installed = Set(
            (NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []).compactMap {
                NSFont(name: $0, size: Self.familyLookupSize)?.familyName
            })
        return installed.union([current]).sorted()
    }

    /// Any size reads a font's family name; it is never drawn.
    private static let familyLookupSize = 12.0

    private static func percent(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        (range.lowerBound * 100).rounded()...(range.upperBound * 100).rounded()
    }

    // MARK: - Painting

    private func paintTexts(_ tokens: AppearancePanelTokens) {
        title.font = theme.interfaceFont(size: tokens.titleFontSize, weight: 600)
        title.textColor = tokens.title.nsColor
        for note in [savedIn, legibilityNote, adjusted] {
            note.font = theme.interfaceFont(size: tokens.noteFontSize)
            note.textColor = tokens.secondary.nsColor
        }
        for label in labels + footerLabels {
            label.attributedStringValue = NSAttributedString(
                string: label.stringValue.uppercased(),
                attributes: [
                    .font: theme.interfaceFont(size: tokens.labelFontSize),
                    .foregroundColor: tokens.secondary.nsColor,
                    .kern: tokens.labelFontSize * tokens.labelTracking,
                ])
        }
        for row in [opacityTitle, blurTitle, legibilityTitle] {
            row.font = theme.interfaceFont(size: tokens.rowFontSize)
            row.textColor = tokens.text.nsColor
        }
        for value in [opacityValue, blurValue] {
            value.font = theme.interfaceFont(size: tokens.rowFontSize)
            value.textColor = tokens.secondary.nsColor
        }
    }

    // MARK: - Layout

    private func layoutPanel() {
        let tokens = theme.appearancePanel
        layer?.borderWidth = 0
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = tokens.border.nsColor.cgColor
        let column = NSStackView(views: [
            header(), section(labels[0], cardGrid(tokens)), glassSection(tokens), ansiSection(tokens),
            section(labels[3], segmentRow(tokens)), footer(tokens),
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = tokens.sectionGap
        for view in [column, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for child in column.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: tokens.borderWidth),
            column.topAnchor.constraint(equalTo: topAnchor, constant: tokens.paddingVertical),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.paddingHorizontal),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.paddingHorizontal),
        ])
    }

    private func header() -> NSView {
        let row = NSStackView(views: [title, NSView(), savedIn])
        row.orientation = .horizontal
        row.distribution = .fill
        return row
    }

    private func section(_ label: NSTextField, _ content: NSView, gap: Double? = nil) -> NSView {
        let stack = NSStackView(views: [label, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = gap ?? theme.appearancePanel.labelGap
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func cardGrid(_ tokens: AppearancePanelTokens) -> NSView {
        let grid = NSGridView(views: [[cards[0], cards[1]], [cards[2], cards[3]]])
        grid.rowSpacing = tokens.cardGap
        grid.columnSpacing = tokens.cardGap
        grid.column(at: 0).xPlacement = .fill
        grid.column(at: 1).xPlacement = .fill
        cards[0].widthAnchor.constraint(equalTo: cards[1].widthAnchor).isActive = true
        return grid
    }

    private func glassSection(_ tokens: AppearancePanelTokens) -> NSView {
        let legibilityText = NSStackView(views: [legibilityTitle, legibilityNote])
        legibilityText.orientation = .vertical
        legibilityText.alignment = .leading
        legibilityText.spacing = tokens.noteGap
        let legibilityRow = NSStackView(views: [legibilityText, NSView(), legibility])
        legibilityRow.orientation = .horizontal
        let rows = NSStackView(views: [
            sliderRow(opacityTitle, opacityValue, opacity), sliderRow(blurTitle, blurValue, blur), legibilityRow,
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = tokens.rowGap
        for row in rows.arrangedSubviews { row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        return section(labels[1], rows, gap: tokens.rowGap)
    }

    private func sliderRow(_ title: NSTextField, _ value: NSTextField, _ slider: NSSlider) -> NSView {
        let top = NSStackView(views: [title, NSView(), value])
        top.orientation = .horizontal
        let stack = NSStackView(views: [top, slider])
        stack.orientation = .vertical
        stack.spacing = theme.appearancePanel.sliderGap
        top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        slider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func ansiSection(_ tokens: AppearancePanelTokens) -> NSView {
        let rows = [Array(swatches[0..<8]), Array(swatches[8..<16])]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = tokens.swatchGap
        grid.columnSpacing = tokens.swatchGap
        let stack = NSStackView(views: [grid, adjusted])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.swatchGap
        return section(labels[2], stack)
    }

    private func segmentRow(_ tokens: AppearancePanelTokens) -> NSView {
        segmentContainer.wantsLayer = true
        segmentContainer.layer?.cornerRadius = tokens.segmentContainerCornerRadius
        segmentContainer.layer?.borderWidth = tokens.segmentContainerBorderWidth
        let row = NSStackView(views: segments.map(\.1))
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        segmentContainer.addSubview(row)
        let inset = tokens.segmentContainerPadding
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: segmentContainer.topAnchor, constant: inset),
            row.bottomAnchor.constraint(equalTo: segmentContainer.bottomAnchor, constant: -inset),
            row.leadingAnchor.constraint(equalTo: segmentContainer.leadingAnchor, constant: inset),
            row.trailingAnchor.constraint(equalTo: segmentContainer.trailingAnchor, constant: -inset),
            row.heightAnchor.constraint(equalToConstant: tokens.segmentHeight),
        ])
        return segmentContainer
    }

    private func footer(_ tokens: AppearancePanelTokens) -> NSView {
        let fontRow = NSStackView(views: [fontFamily, fontSize])
        fontRow.orientation = .horizontal
        fontRow.spacing = tokens.stepperGap
        let columns = zip(footerLabels, [fontRow, gap, radius] as [NSView]).map { label, value in
            let column = NSStackView(views: [label, value])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = tokens.footerGap
            return column as NSView
        }
        let grid = NSStackView(views: columns)
        grid.orientation = .horizontal
        grid.distribution = .fillEqually
        grid.spacing = tokens.cardGap
        return grid
    }
}
