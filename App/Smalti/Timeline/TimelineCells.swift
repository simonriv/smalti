import AppKit
import SmaltiCore

/// The list's cells, built fresh for the visible rows only.
@MainActor
struct TimelineCells {
    let theme: Theme
    private var tokens: TimelineTokens { theme.timeline }

    // MARK: - Session rows

    func row(_ row: TimelineRow, index: Int, isSelected: Bool) -> NSView {
        let content: NSView =
            switch row.kind {
            case .prompt, .reply: textItem(row)
            case .tool: toolItem(row)
            case .image, .compaction: noteItem(row)
            }
        let cell = TimelineCell(
            content: content, theme: theme, isSelected: isSelected, indent: Double(row.depth) * tokens.childIndent)
        cell.setAccessibilityIdentifier("smalti.timeline.item.\(index)")
        cell.setAccessibilityLabel(
            [row.who, row.time ?? "", row.summary ?? row.text, row.statusText ?? ""].filter { !$0.isEmpty }.joined(
                separator: ", "))
        cell.setAccessibilityValue(isSelected ? "selected" : (row.isExpanded ? "expanded" : ""))
        return cell
    }

    private func who(_ text: String, time: String?) -> NSView {
        let label = ObservatoryText.caption(text, theme: theme)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let clock = ObservatoryText.number(time ?? "", .init(size: 10.5, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [label, spacer, clock])
        stack.spacing = 8
        return stack
    }

    private func wrapping(_ text: String, size: Double, color: RGBAColor, lines: Int) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = theme.interfaceFont(size: size)
        field.textColor = color.nsColor
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.preferredMaxLayoutWidth = tokens.width - tokens.itemPaddingLeading - tokens.padding - 20
        field.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        return field
    }

    private func textItem(_ row: TimelineRow) -> NSView {
        let isPrompt = row.kind == .prompt
        let text = wrapping(
            row.text, size: tokens.textFontSize, color: isPrompt ? theme.text.title : theme.text.primary,
            lines: isPrompt ? tokens.promptLines : tokens.replyLines)
        let body: NSView
        if isPrompt {
            let edge = NSBox()
            edge.boxType = .custom
            edge.borderWidth = 0
            edge.fillColor = tokens.promptEdge.nsColor
            edge.widthAnchor.constraint(equalToConstant: tokens.promptEdgeWidth).isActive = true
            let stack = NSStackView(views: [edge, text])
            stack.spacing = tokens.promptEdgeGap
            stack.alignment = .top
            edge.heightAnchor.constraint(equalTo: text.heightAnchor).isActive = true
            body = stack
        } else {
            body = text
        }
        let stack = NSStackView(views: [who(row.who, time: row.time), body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.itemPaddingVertical, left: 0, bottom: tokens.itemPaddingVertical, right: 0)
        return stack
    }

    private func toolItem(_ row: TimelineRow) -> NSView {
        let chevron = ObservatoryText.label(
            row.isExpanded ? "▾" : "▸", .init(size: 10, color: theme.text.secondary), theme: theme)
        let name = ObservatoryText.number(
            row.who.isEmpty ? "?" : row.who, .init(size: tokens.monoFontSize, color: tokens.toolName), theme: theme)
        let summary = ObservatoryText.number(
            row.summary ?? "", .init(size: tokens.monoFontSize, color: theme.text.secondary), theme: theme)
        summary.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        summary.setContentHuggingPriority(.init(1), for: .horizontal)
        let line = NSStackView(views: [chevron, name, summary] + status(row))
        line.spacing = 8
        line.heightAnchor.constraint(equalToConstant: tokens.toolRowHeight).isActive = true
        guard row.isExpanded, let output = row.expandedText else { return line }
        let stack = NSStackView(views: [line, outputBlock(row, output)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func status(_ row: TimelineRow) -> [NSView] {
        guard let status = row.status, let text = row.statusText else { return [] }
        let color = tokens.color(for: status)
        let mark: NSView =
            switch status {
            case .done: ObservatoryText.label("✓", .init(size: 11, color: color), theme: theme)
            case .working, .failed: StatusDot(diameter: theme.header.dotSize, color: color)
            }
        let label = ObservatoryText.label(
            text, .init(size: 11, color: status == .done ? theme.text.secondary : color), theme: theme)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [mark, label])
        stack.spacing = 5
        return [stack]
    }

    private func outputBlock(_ row: TimelineRow, _ output: String) -> NSView {
        let label = ObservatoryText.caption(row.expandedLabel ?? "", theme: theme)
        let text = NSTextField(wrappingLabelWithString: output)
        text.font = theme.monospacedFont(size: tokens.monoFontSize)
        text.textColor = theme.text.primary.nsColor
        text.preferredMaxLayoutWidth = tokens.width - 80
        text.setAccessibilityIdentifier("smalti.timeline.output")
        var views: [NSView] = [label, text]
        if row.moreLines > 0 {
            let more = TimelineTexts.current.moreLines(row.moreLines, ["copy": "⌘C"])
            views.append(ObservatoryText.label(more, .init(size: 11, color: theme.text.secondary), theme: theme))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 7, left: tokens.outputPadding, bottom: 7, right: tokens.outputPadding)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = tokens.outputRadius
        stack.layer?.backgroundColor = tokens.outputBackground.nsColor.cgColor
        let indent = NSStackView(views: [stack])
        indent.edgeInsets = NSEdgeInsets(top: 0, left: tokens.childIndent, bottom: 4, right: 0)
        return indent
    }

    private func noteItem(_ row: TimelineRow) -> NSView {
        let label = ObservatoryText.label(row.text, .init(size: 11, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [label])
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return stack
    }

    // MARK: - Search

    func group(title: String, meta: String, count: Int) -> NSView {
        let name = ObservatoryText.label(title, .init(size: 11.5, color: theme.text.title, weight: 500), theme: theme)
        name.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let number = ObservatoryText.number(String(count), .init(size: 11, color: theme.text.secondary), theme: theme)
        let first = NSStackView(views: [name, spacer, number])
        let second = ObservatoryText.label(meta, .init(size: 10.5, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [first, second])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 9, left: tokens.padding, bottom: 4, right: tokens.padding)
        first.widthAnchor.constraint(equalToConstant: tokens.width - 2 * tokens.padding).isActive = true
        return stack
    }

    func hit(who: String, time: String, snippet: String, match: NSRange, isSelected: Bool, number: Int) -> NSView {
        let text = NSMutableAttributedString(
            string: snippet,
            attributes: [.font: theme.interfaceFont(size: 12), .foregroundColor: theme.text.primary.nsColor])
        if match.location != NSNotFound, NSMaxRange(match) <= text.length {
            text.addAttributes(
                [.backgroundColor: tokens.matchHighlight.nsColor, .foregroundColor: theme.text.title.nsColor],
                range: match)
        }
        let field = NSTextField(labelWithAttributedString: text)
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byTruncatingTail
        field.preferredMaxLayoutWidth = tokens.width - tokens.itemPaddingLeading - tokens.padding - 20
        let stack = NSStackView(views: [self.who(who, time: time), field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        let cell = TimelineCell(content: stack, theme: theme, isSelected: isSelected, indent: 0)
        cell.setAccessibilityIdentifier("smalti.timeline.hit.\(number)")
        cell.setAccessibilityLabel("\(who), \(time), \(snippet)")
        cell.setAccessibilityValue(isSelected ? "selected" : "")
        return cell
    }

    // MARK: - Empty and fallback

    func message(title: String, body: String) -> NSView {
        let dot = StatusDot(diameter: 10, style: .hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth))
        let heading = wrapping(title, size: tokens.emptyTitleSize, color: theme.text.title, lines: 3)
        heading.font = theme.interfaceFont(size: tokens.emptyTitleSize, weight: 600)
        heading.setAccessibilityIdentifier("smalti.timeline.empty")
        var views: [NSView] = [dot, heading]
        if !body.isEmpty {
            views.append(wrapping(body, size: tokens.emptyBodySize, color: theme.text.primary, lines: 6))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 6, right: 22)
        return stack
    }

    func caption(_ text: String) -> NSView {
        let label = ObservatoryText.caption(text, theme: theme)
        let stack = NSStackView(views: [label])
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 22, bottom: 4, right: 22)
        return stack
    }

    func recent(_ recent: TimelineScreen.Recent, isSelected: Bool, number: Int) -> NSView {
        let dot = StatusDot(
            diameter: theme.header.dotSize,
            style: recent.isLive
                ? .filled(theme.agent.working) : .hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth))
        let title = ObservatoryText.label(recent.title, .init(size: 12, color: theme.text.title), theme: theme)
        title.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let meta = ObservatoryText.label(recent.meta, .init(size: 11, color: theme.text.secondary), theme: theme)
        let line = NSStackView(views: [dot, title, spacer, meta])
        line.spacing = 9
        line.heightAnchor.constraint(equalToConstant: tokens.recentRowHeight).isActive = true
        let cell = TimelineCell(content: line, theme: theme, isSelected: isSelected, indent: 6)
        cell.setAccessibilityIdentifier("smalti.timeline.recent.\(number)")
        cell.setAccessibilityLabel("\(recent.title), \(recent.meta)")
        cell.setAccessibilityValue(isSelected ? "selected" : "")
        return cell
    }
}

/// A list row: its content padded, with the accent's glow and 2 pt edge when chosen.
@MainActor
final class TimelineCell: NSTableCellView {
    init(content: NSView, theme: Theme, isSelected: Bool, indent: Double) {
        super.init(frame: .zero)
        let tokens = theme.timeline
        wantsLayer = true
        layer?.backgroundColor = (isSelected ? theme.focus.glow.nsColor : NSColor.clear).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: tokens.itemPaddingLeading + indent),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -tokens.padding),
        ])
        if isSelected {
            let edge = NSBox()
            edge.boxType = .custom
            edge.borderWidth = 0
            edge.fillColor = theme.accent.nsColor
            edge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(edge)
            NSLayoutConstraint.activate([
                edge.leadingAnchor.constraint(equalTo: leadingAnchor), edge.topAnchor.constraint(equalTo: topAnchor),
                edge.bottomAnchor.constraint(equalTo: bottomAnchor),
                edge.widthAnchor.constraint(equalToConstant: tokens.selectionEdgeWidth),
            ])
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}
