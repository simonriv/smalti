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
            content: content, theme: theme, isSelected: isSelected, indent: Double(row.depth) * tokens.childIndent,
            guides: row.depth)
        cell.setAccessibilityIdentifier("smalti.timeline.item.\(index)")
        cell.setAccessibilityLabel(
            [row.who, row.time ?? "", row.summary ?? row.text, row.statusText ?? ""].filter { !$0.isEmpty }.joined(
                separator: ", "))
        cell.setAccessibilitySelected(isSelected)
        if row.kind == .tool { cell.setAccessibilityExpanded(row.isExpanded) }
        return cell
    }

    private func who(_ text: String, time: String?) -> NSView {
        let label = ObservatoryText.caption(text, theme: theme)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let clock = ObservatoryText.number(
            time ?? "", .init(size: tokens.whoFontSize, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [label, spacer, clock])
        stack.spacing = tokens.whoGap
        return stack
    }

    private func wrapping(_ text: String, size: Double, color: RGBAColor, lines: Int) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = theme.interfaceFont(size: size)
        field.textColor = color.nsColor
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.preferredMaxLayoutWidth =
            tokens.width - tokens.itemPaddingLeading - tokens.padding - tokens.textWidthInset
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
        stack.spacing = tokens.textGap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.itemPaddingVertical, left: 0, bottom: tokens.itemPaddingVertical, right: 0)
        return stack
    }

    private func toolItem(_ row: TimelineRow) -> NSView {
        let chevron = ObservatoryText.label(
            row.isExpanded ? "▾" : "▸", .init(size: tokens.chevronSize, color: theme.text.secondary), theme: theme)
        let name = ObservatoryText.number(
            row.who.isEmpty ? "?" : row.who, .init(size: tokens.monoFontSize, color: tokens.toolName), theme: theme)
        let summary = ObservatoryText.number(
            row.summary ?? "", .init(size: tokens.monoFontSize, color: theme.text.secondary), theme: theme)
        summary.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        summary.setContentHuggingPriority(.init(1), for: .horizontal)
        let line = NSStackView(views: [chevron, name, summary] + status(row))
        line.spacing = tokens.toolGap
        line.heightAnchor.constraint(equalToConstant: tokens.toolRowHeight).isActive = true
        guard row.isExpanded, let output = row.expandedText else { return line }
        let stack = NSStackView(views: [line, outputBlock(row, output)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.outputBottom
        return stack
    }

    private func status(_ row: TimelineRow) -> [NSView] {
        guard let status = row.status, let text = row.statusText else { return [] }
        let color = tokens.color(for: status)
        let mark: NSView =
            switch status {
            case .done: ObservatoryText.label("✓", .init(size: tokens.smallFontSize, color: color), theme: theme)
            case .working, .failed: StatusDot(diameter: theme.header.dotSize, color: color)
            }
        let label = ObservatoryText.label(
            text, .init(size: tokens.smallFontSize, color: status == .done ? theme.text.secondary : color), theme: theme
        )
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [mark, label])
        stack.spacing = tokens.statusGap
        return [stack]
    }

    private func outputBlock(_ row: TimelineRow, _ output: String) -> NSView {
        let label = ObservatoryText.caption(row.expandedLabel ?? "", theme: theme)
        let text = NSTextField(wrappingLabelWithString: output)
        text.font = theme.monospacedFont(size: tokens.monoFontSize)
        text.textColor = theme.text.primary.nsColor
        text.preferredMaxLayoutWidth = tokens.width - tokens.outputWidthInset
        text.setAccessibilityIdentifier("smalti.timeline.output")
        var views: [NSView] = [label, text]
        if row.moreLines > 0 {
            let more = TimelineTexts.current.moreLines(row.moreLines, ["copy": "⌘C"])
            views.append(
                ObservatoryText.label(
                    more, .init(size: tokens.smallFontSize, color: theme.text.secondary), theme: theme))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.outputGap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.outputPaddingVertical, left: tokens.outputPadding, bottom: tokens.outputPaddingVertical,
            right: tokens.outputPadding)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = tokens.outputRadius
        stack.layer?.backgroundColor = tokens.outputBackground.nsColor.cgColor
        let indent = NSStackView(views: [stack])
        indent.edgeInsets = NSEdgeInsets(top: 0, left: tokens.childIndent, bottom: tokens.outputBottom, right: 0)
        return indent
    }

    private func noteItem(_ row: TimelineRow) -> NSView {
        let label = ObservatoryText.label(
            row.text, .init(size: tokens.smallFontSize, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [label])
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.notePaddingVertical, left: 0, bottom: tokens.notePaddingVertical, right: 0)
        return stack
    }

    // MARK: - Search

    func group(title: String, meta: String, count: Int) -> NSView {
        let name = ObservatoryText.label(
            title, .init(size: tokens.groupTitleSize, color: theme.text.title, weight: tokens.mediumWeight),
            theme: theme)
        name.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let number = ObservatoryText.number(
            String(count), .init(size: tokens.smallFontSize, color: theme.text.secondary), theme: theme)
        let first = NSStackView(views: [name, spacer, number])
        let second = ObservatoryText.label(
            meta, .init(size: tokens.whoFontSize, color: theme.text.secondary), theme: theme)
        let stack = NSStackView(views: [first, second])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.groupGap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.groupPaddingTop, left: tokens.padding, bottom: tokens.groupPaddingBottom, right: tokens.padding)
        first.widthAnchor.constraint(equalToConstant: tokens.width - 2 * tokens.padding).isActive = true
        return stack
    }

    func hit(who: String, time: String, snippet: String, match: NSRange, isSelected: Bool, number: Int) -> NSView {
        let text = NSMutableAttributedString(
            string: snippet,
            attributes: [
                .font: theme.interfaceFont(size: tokens.hitFontSize), .foregroundColor: theme.text.primary.nsColor,
            ])
        if match.location != NSNotFound, NSMaxRange(match) <= text.length {
            text.addAttributes(
                [.backgroundColor: tokens.matchHighlight.nsColor, .foregroundColor: theme.text.title.nsColor],
                range: match)
        }
        let field = NSTextField(labelWithAttributedString: text)
        field.maximumNumberOfLines = tokens.hitLines
        field.lineBreakMode = .byTruncatingTail
        field.preferredMaxLayoutWidth =
            tokens.width - tokens.itemPaddingLeading - tokens.padding - tokens.textWidthInset
        let stack = NSStackView(views: [self.who(who, time: time), field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.hitGap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.hitPaddingVertical, left: 0, bottom: tokens.hitPaddingVertical, right: 0)
        let cell = TimelineCell(content: stack, theme: theme, isSelected: isSelected, indent: 0)
        cell.setAccessibilityIdentifier("smalti.timeline.hit.\(number)")
        cell.setAccessibilityLabel("\(who), \(time), \(snippet)")
        cell.setAccessibilitySelected(isSelected)
        return cell
    }

    // MARK: - Empty and fallback

    func message(title: String, body: String) -> NSView {
        let dot = StatusDot(
            diameter: tokens.emptyDotSize, style: .hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth))
        let heading = wrapping(
            title, size: tokens.emptyTitleSize, color: theme.text.title, lines: tokens.emptyTitleLines)
        heading.font = theme.interfaceFont(size: tokens.emptyTitleSize, weight: tokens.titleWeight)
        heading.setAccessibilityIdentifier("smalti.timeline.empty")
        var views: [NSView] = [dot, heading]
        if !body.isEmpty {
            views.append(
                wrapping(body, size: tokens.emptyBodySize, color: theme.text.primary, lines: tokens.emptyBodyLines))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = tokens.emptyGap
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.emptyPaddingTop, left: tokens.emptyPaddingHorizontal, bottom: tokens.emptyPaddingBottom,
            right: tokens.emptyPaddingHorizontal)
        return stack
    }

    func caption(_ text: String) -> NSView {
        let label = ObservatoryText.caption(text, theme: theme)
        let stack = NSStackView(views: [label])
        stack.edgeInsets = NSEdgeInsets(
            top: tokens.captionPaddingTop, left: tokens.emptyPaddingHorizontal, bottom: tokens.captionPaddingBottom,
            right: tokens.emptyPaddingHorizontal)
        return stack
    }

    func recent(_ recent: TimelineScreen.Recent, isSelected: Bool, number: Int) -> NSView {
        let dot = StatusDot(
            diameter: theme.header.dotSize,
            style: recent.isLive
                ? .filled(theme.agent.working) : .hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth))
        let title = ObservatoryText.label(
            recent.title, .init(size: tokens.recentFontSize, color: theme.text.title), theme: theme)
        title.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let meta = ObservatoryText.label(
            recent.meta, .init(size: tokens.smallFontSize, color: theme.text.secondary), theme: theme)
        let line = NSStackView(views: [dot, title, spacer, meta])
        line.spacing = tokens.recentGap
        line.heightAnchor.constraint(equalToConstant: tokens.recentRowHeight).isActive = true
        let cell = TimelineCell(content: line, theme: theme, isSelected: isSelected, indent: tokens.recentIndent)
        cell.setAccessibilityIdentifier("smalti.timeline.recent.\(number)")
        cell.setAccessibilityLabel("\(recent.title), \(recent.meta)")
        cell.setAccessibilitySelected(isSelected)
        return cell
    }
}

/// A list row: its content padded, with the accent's glow and 2 pt edge when chosen.
@MainActor
final class TimelineCell: NSTableCellView {
    init(content: NSView, theme: Theme, isSelected: Bool, indent: Double, guides: Int = 0) {
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
        for level in 0..<guides {
            addGuide(at: tokens.itemPaddingLeading + Double(level) * tokens.childIndent, theme: theme)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
    }

    /// One guide per subagent level on the left (spec F9: subagents sit 18 pt in, with a guide).
    private func addGuide(at x: Double, theme: Theme) {
        let guide = NSBox()
        guide.boxType = .custom
        guide.borderWidth = 0
        guide.fillColor = theme.timeline.guide.nsColor
        guide.translatesAutoresizingMaskIntoConstraints = false
        addSubview(guide)
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x),
            guide.topAnchor.constraint(equalTo: topAnchor), guide.bottomAnchor.constraint(equalTo: bottomAnchor),
            guide.widthAnchor.constraint(equalToConstant: theme.timeline.guideWidth),
        ])
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }
}
