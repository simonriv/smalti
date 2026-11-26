import AppKit
import SmaltiCore

/// What the studio shows: the draft, its previews in the board's three situations, and whether a Nerd Font exists.
struct PromptStudioState {
    let draft: PromptConfig
    let previews: [(title: String, lines: [[PreviewRun]])]
    let moduleList: [ModuleRow]
    let theme: Theme
    let hasNerdFont: Bool
}

/// The studio's edits; the controller turns them into `EditPrompt` calls.
enum PromptStudioEdit {
    case template(PromptTemplate)
    case toggle(PromptModuleID)
    case move(PromptModuleID, by: Int)
    case icons(PromptIcons)
    case symbol(PromptSymbol)
    case toggleLayout
    case toggleShellPrompt
    case apply
    case export
}

/// `Prompt.dc.html`: the previews, templates and buttons on the left; modules, icons, symbol and layout on the right.
/// It covers the whole window; the panes behind it stay alive.
@MainActor
final class PromptStudioView: NSView {
    var onEdit: ((PromptStudioEdit) -> Void)?

    private let title = NSTextField(labelWithString: "Prompt")
    private let subtitle = NSTextField(labelWithString: String(localized: "preview in three real situations"))
    private let previewBox = NSView()
    private let previewStack = NSStackView()
    private let templates = PromptTemplate.allCases.map { TemplateCardView(template: $0) }
    private let apply = PanelButtonView(
        identifier: "smalti.studio.apply", label: String(localized: "Apply to All Panes"))
    private let applyLabel = NSTextField(labelWithString: String(localized: "Apply to All Panes"))
    private let export = PanelButtonView(
        identifier: "smalti.studio.export", label: String(localized: "Export as starship.toml"))
    private let exportLabel = NSTextField(labelWithString: String(localized: "Export as starship.toml"))
    private let exportNote = NSTextField(
        labelWithString: String(localized: "to use the same prompt over SSH or in another terminal"))
    private let aside = NSView()
    private let modulesNote = NSTextField(
        labelWithString: String(localized: "Drag to reorder. Each one appears only when it applies."))
    private let moduleStack = NSStackView()
    private let iconSegments = PromptIcons.allCases.map {
        SegmentView(
            identifier: "smalti.studio.icons.\($0.rawValue)", title: $0.title(.current),
            inset: Theme.obsidian.appearancePanel.segmentLabelInset)
    }
    private let noNerdFont = NSTextField(labelWithString: PromptCopy.current.noNerdFont)
    private let symbols = PromptSymbol.allCases.map {
        SegmentView(
            identifier: "smalti.studio.symbol.\($0.rawValue)", title: $0.rawValue,
            inset: Theme.obsidian.appearancePanel.segmentLabelInset)
    }
    private let layoutChoice = PanelButtonView(identifier: "smalti.studio.layout", label: String(localized: "Layout"))
    private let layoutLabel = NSTextField(labelWithString: "")
    private let shellPrompt = NSButton(checkboxWithTitle: PromptCopy.current.shellPrompt, target: nil, action: nil)
    private let labels = [
        String(localized: "Templates"), String(localized: "Modules"), String(localized: "Icons"),
        String(localized: "Symbol"), String(localized: "Layout"),
    ].map {
        NSTextField(labelWithString: $0)
    }
    private var theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("smalti.studio")
        aside.setAccessibilityElement(true)
        aside.setAccessibilityRole(.group)
        aside.setAccessibilityIdentifier("smalti.studio.aside")
        shellPrompt.setAccessibilityIdentifier("smalti.studio.shellPrompt")
        connect()
        layoutStudio()
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    var firstControl: NSView { templates[0] }

    func render(_ state: PromptStudioState) {
        theme = state.theme
        let panel = theme.appearancePanel
        let tokens = theme.promptStudio
        aside.layer?.backgroundColor = panel.background(protectedAt: 0).nsColor.cgColor
        previewBox.layer?.backgroundColor = tokens.previewBackground.nsColor.cgColor
        previewBox.layer?.borderColor = tokens.previewBorder.nsColor.cgColor
        paintTexts()
        renderPreviews(state.previews)
        let current = state.draft.template
        for card in templates { card.render(isSelected: card.template == current, theme: theme) }
        renderModules(state.moduleList)
        for (icons, segment) in zip(PromptIcons.allCases, iconSegments) {
            segment.render(isSelected: icons == state.draft.icons, theme: theme)
        }
        let nerd = iconSegments[PromptIcons.allCases.firstIndex(of: .nerd) ?? 1]
        nerd.isEnabledChoice = state.hasNerdFont
        noNerdFont.isHidden = state.hasNerdFont
        for (symbol, segment) in zip(PromptSymbol.allCases, symbols) {
            segment.render(isSelected: symbol == state.draft.symbol, theme: theme)
        }
        layoutLabel.stringValue = state.draft.layout.title(.current)
        layoutChoice.setAccessibilityValue(state.draft.layout.title(.current))
        shellPrompt.state = state.draft.source == .shell ? .on : .off
        paintButtons(tokens)
    }

    override func cancelOperation(_ sender: Any?) {}

    // MARK: - Pieces

    private func connect() {
        for card in templates {
            card.action = { [weak self, template = card.template] in self?.onEdit?(.template(template)) }
        }
        for (icons, segment) in zip(PromptIcons.allCases, iconSegments) {
            segment.action = { [weak self, weak segment] in
                guard segment?.isEnabledChoice != false else { return }
                self?.onEdit?(.icons(icons))
            }
        }
        for (symbol, segment) in zip(PromptSymbol.allCases, symbols) {
            segment.action = { [weak self] in self?.onEdit?(.symbol(symbol)) }
        }
        layoutChoice.action = { [weak self] in self?.onEdit?(.toggleLayout) }
        shellPrompt.target = self
        shellPrompt.action = #selector(toggledShellPrompt)
        apply.action = { [weak self] in self?.onEdit?(.apply) }
        export.action = { [weak self] in self?.onEdit?(.export) }
    }

    @objc private func toggledShellPrompt() { onEdit?(.toggleShellPrompt) }

    private func renderPreviews(_ previews: [(title: String, lines: [[PreviewRun]])]) {
        let tokens = theme.promptStudio
        previewStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, preview) in previews.enumerated() {
            if index > 0 {
                let line = NSView()
                line.wantsLayer = true
                line.layer?.backgroundColor = tokens.separator.nsColor.cgColor
                line.heightAnchor.constraint(equalToConstant: tokens.separatorHeight).isActive = true
                previewStack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: previewStack.widthAnchor).isActive = true
            }
            let label = NSTextField(labelWithString: preview.title)
            paintLabel(label)
            let text = NSTextField(labelWithAttributedString: PromptRunText.attributed(preview.lines, theme: theme))
            text.setAccessibilityIdentifier("smalti.studio.preview")
            let section = NSStackView(views: [label, text])
            section.orientation = .vertical
            section.alignment = .leading
            section.spacing = tokens.previewLabelGap
            previewStack.addArrangedSubview(section)
        }
    }

    /// The rows are built again on every edit; the focused module keeps the focus (block 5 review, I3).
    private func renderModules(_ rows: [ModuleRow]) {
        let focused = (window?.firstResponder as? ModuleRowView)?.module
        moduleStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in rows {
            let view = ModuleRowView(row: row, theme: theme)
            if row.id == focused { DispatchQueue.main.async { [weak view] in view?.window?.makeFirstResponder(view) } }
            view.onToggle = { [weak self] in self?.onEdit?(.toggle(row.id)) }
            view.onMove = { [weak self] offset in self?.onEdit?(.move(row.id, by: offset)) }
            moduleStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: moduleStack.widthAnchor).isActive = true
        }
    }

    private func paintTexts() {
        let panel = theme.appearancePanel
        title.font = theme.interfaceFont(size: panel.titleFontSize, weight: 600)
        title.textColor = panel.title.nsColor
        for note in [subtitle, modulesNote, exportNote, noNerdFont] {
            note.font = theme.interfaceFont(size: panel.noteFontSize)
            note.textColor = panel.secondary.nsColor
        }
        labels.forEach(paintLabel)
        layoutLabel.font = theme.interfaceFont(size: panel.rowFontSize)
        layoutLabel.textColor = panel.text.nsColor
        shellPrompt.attributedTitle = NSAttributedString(
            string: PromptCopy.current.shellPrompt,
            attributes: [.font: theme.interfaceFont(size: panel.rowFontSize), .foregroundColor: panel.text.nsColor])
    }

    private func paintLabel(_ label: NSTextField) {
        let panel = theme.appearancePanel
        label.attributedStringValue = NSAttributedString(
            string: label.stringValue.uppercased(),
            attributes: [
                .font: theme.interfaceFont(size: panel.labelFontSize), .foregroundColor: panel.secondary.nsColor,
                .kern: panel.labelFontSize * panel.labelTracking,
            ])
    }

    private func paintButtons(_ tokens: PromptStudioTokens) {
        let panel = theme.appearancePanel
        apply.layer?.backgroundColor = tokens.applyBackground.nsColor.cgColor
        apply.layer?.cornerRadius = tokens.buttonCornerRadius
        applyLabel.font = theme.interfaceFont(size: panel.rowFontSize, weight: 600)
        applyLabel.textColor = tokens.applyText.nsColor
        export.layer?.borderColor = tokens.exportBorder.nsColor.cgColor
        export.layer?.borderWidth = panel.borderWidth
        export.layer?.cornerRadius = tokens.buttonCornerRadius
        exportLabel.font = theme.interfaceFont(size: panel.rowFontSize, weight: 500)
        exportLabel.textColor = tokens.exportText.nsColor
    }

    // MARK: - Layout

    private func layoutStudio() {
        let tokens = theme.promptStudio
        let main = mainColumn(tokens)
        buildAside(tokens)
        for view in [main, aside] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: topAnchor, constant: tokens.mainPaddingVertical),
            main.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -tokens.mainPaddingVertical),
            main.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.mainPaddingHorizontal),
            main.trailingAnchor.constraint(equalTo: aside.leadingAnchor, constant: -tokens.mainPaddingHorizontal),
            aside.topAnchor.constraint(equalTo: topAnchor),
            aside.bottomAnchor.constraint(equalTo: bottomAnchor),
            aside.trailingAnchor.constraint(equalTo: trailingAnchor),
            aside.widthAnchor.constraint(equalToConstant: tokens.asideWidth),
        ])
    }

    private func mainColumn(_ tokens: PromptStudioTokens) -> NSView {
        let header = NSStackView(views: [title, NSView(), subtitle])
        header.orientation = .horizontal
        previewBox.wantsLayer = true
        previewBox.layer?.cornerRadius = tokens.previewCornerRadius
        previewBox.layer?.borderWidth = theme.appearancePanel.borderWidth
        previewStack.orientation = .vertical
        previewStack.alignment = .leading
        previewStack.spacing = tokens.previewGap
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewBox.addSubview(previewStack)
        NSLayoutConstraint.activate([
            previewStack.topAnchor.constraint(equalTo: previewBox.topAnchor, constant: tokens.previewPaddingVertical),
            previewStack.bottomAnchor.constraint(
                equalTo: previewBox.bottomAnchor, constant: -tokens.previewPaddingVertical),
            previewStack.leadingAnchor.constraint(
                equalTo: previewBox.leadingAnchor, constant: tokens.previewPaddingHorizontal),
            previewStack.trailingAnchor.constraint(
                equalTo: previewBox.trailingAnchor, constant: -tokens.previewPaddingHorizontal),
        ])
        let cards = NSStackView(views: templates)
        cards.orientation = .horizontal
        cards.distribution = .fillEqually
        cards.spacing = tokens.templateGap
        let templatesSection = NSStackView(views: [labels[0], cards])
        templatesSection.orientation = .vertical
        templatesSection.alignment = .leading
        templatesSection.spacing = theme.appearancePanel.labelGap
        cards.widthAnchor.constraint(equalTo: templatesSection.widthAnchor).isActive = true
        let buttons = NSStackView(views: [
            button(apply, applyLabel, tokens), button(export, exportLabel, tokens), exportNote,
        ])
        buttons.orientation = .horizontal
        buttons.spacing = tokens.buttonGap
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let column = NSStackView(views: [header, previewBox, templatesSection, spacer, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = tokens.mainGap
        for child in [header, previewBox, templatesSection] {
            child.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        return column
    }

    private func button(_ box: PanelButtonView, _ label: NSTextField, _ tokens: PromptStudioTokens) -> NSView {
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: tokens.buttonHeight),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: tokens.buttonPadding),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -tokens.buttonPadding),
        ])
        return box
    }

    private func buildAside(_ tokens: PromptStudioTokens) {
        aside.wantsLayer = true
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = theme.appearancePanel.border.nsColor.cgColor
        let modulesHeader = NSStackView(views: [labels[1], modulesNote])
        modulesHeader.orientation = .vertical
        modulesHeader.alignment = .leading
        modulesHeader.spacing = tokens.noteGap
        moduleStack.orientation = .vertical
        moduleStack.spacing = tokens.moduleRowGap
        let icons = segmentRow(iconSegments)
        let iconsSection = NSStackView(views: [labels[2], icons, noNerdFont])
        iconsSection.orientation = .vertical
        iconsSection.alignment = .leading
        iconsSection.spacing = tokens.sectionInnerGap
        icons.widthAnchor.constraint(equalTo: iconsSection.widthAnchor).isActive = true
        layoutLabel.translatesAutoresizingMaskIntoConstraints = false
        layoutChoice.addSubview(layoutLabel)
        NSLayoutConstraint.activate([
            layoutLabel.topAnchor.constraint(equalTo: layoutChoice.topAnchor),
            layoutLabel.bottomAnchor.constraint(equalTo: layoutChoice.bottomAnchor),
            layoutLabel.leadingAnchor.constraint(equalTo: layoutChoice.leadingAnchor),
            layoutLabel.trailingAnchor.constraint(equalTo: layoutChoice.trailingAnchor),
        ])
        let symbolColumn = gridColumn(labels[3], segmentRow(symbols))
        let layoutColumn = gridColumn(labels[4], layoutChoice, shellPrompt)
        let grid = NSStackView(views: [symbolColumn, layoutColumn])
        grid.orientation = .horizontal
        grid.distribution = .fillEqually
        grid.alignment = .top
        grid.spacing = tokens.gridGap
        let column = NSStackView(views: [modulesHeader, moduleStack, iconsSection, grid])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = tokens.asideGap
        for child in column.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        for view in [column, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            aside.addSubview(view)
        }
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: aside.leadingAnchor),
            border.topAnchor.constraint(equalTo: aside.topAnchor),
            border.bottomAnchor.constraint(equalTo: aside.bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: theme.appearancePanel.borderWidth),
            column.topAnchor.constraint(equalTo: aside.topAnchor, constant: tokens.asidePaddingVertical),
            column.leadingAnchor.constraint(equalTo: aside.leadingAnchor, constant: tokens.asidePaddingHorizontal),
            column.trailingAnchor.constraint(equalTo: aside.trailingAnchor, constant: -tokens.asidePaddingHorizontal),
        ])
    }

    private func gridColumn(_ label: NSTextField, _ views: NSView...) -> NSView {
        let column = NSStackView(views: [label] + views)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = theme.promptStudio.gridInnerGap
        return column
    }

    private func segmentRow(_ segments: [SegmentView]) -> NSView {
        let panel = theme.appearancePanel
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = panel.segmentContainerCornerRadius
        container.layer?.borderWidth = panel.segmentContainerBorderWidth
        container.layer?.backgroundColor = panel.segmentContainer.nsColor.cgColor
        container.layer?.borderColor = panel.segmentContainerBorder.nsColor.cgColor
        let row = NSStackView(views: segments)
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        let inset = panel.segmentContainerPadding
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            row.heightAnchor.constraint(equalToConstant: panel.segmentHeight),
        ])
        return container
    }
}
