import AppKit
import SmaltiCore

/// The four cards: active sessions, input tokens, output tokens and the API equivalent.
@MainActor
final class SummaryCardsView: NSStackView {
    private struct Card {
        let view: ObservatoryCard
        let value: NSTextField
        let note: NSTextField
    }

    private let theme: Theme
    private var cards: [Card] = []

    private static let titles = ["Sesiones activas", "Tokens entrada", "Tokens salida", "Equivalente API"]
    private static let identifiers = ["sessions", "input", "output", "cost"]
    static let reading = "leyendo transcripts…"

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        orientation = .horizontal
        distribution = .fillEqually
        spacing = theme.observatory.cardGap
        cards = zip(Self.titles, Self.identifiers).map { makeCard(title: $0, identifier: $1) }
        setViews(cards.map(\.view), in: .leading)
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    private func makeCard(title: String, identifier: String) -> Card {
        let tokens = theme.observatory
        let card = ObservatoryCard(theme: theme, spacing: tokens.spacing.cardStack)
        let value = ObservatoryText.number("", .init(size: tokens.valueSize, color: theme.text.title), theme: theme)
        let note = ObservatoryText.label("", .init(size: tokens.noteSize, color: theme.text.secondary), theme: theme)
        // A long note ("… · sin precio para 1 modelo") truncates instead of widening its card: the four stay equal.
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        card.content.setViews([ObservatoryText.caption(title, theme: theme), value, note], in: .leading)
        card.setAccessibilityElement(true)
        card.setAccessibilityRole(.group)
        card.setAccessibilityIdentifier("smalti.observatory.card.\(identifier)")
        return Card(view: card, value: value, note: note)
    }

    func show(_ summary: ObservatoryReport.Summary, timeZone: TimeZone) {
        guard cards.count == Self.titles.count else { return }
        set(cards[0], value: String(summary.active), note: sessionsNote(summary))
        guard summary.isComplete else {
            cards.dropFirst().forEach { set($0, value: "—", note: plain(Self.reading)) }
            return
        }
        set(
            cards[1], value: ObservatoryFormat.count(summary.input),
            note: plain(ObservatoryTexts.cache(summary, copy: .spanish /* T9 */)))
        set(
            cards[2], value: ObservatoryFormat.count(summary.output),
            note: plain(ObservatoryTexts.peak(summary, timeZone: timeZone, copy: .spanish /* T9 */)))
        set(
            cards[3], value: ObservatoryFormat.usd(summary.cost.usd),
            note: plain(ObservatoryTexts.cost(summary, copy: .spanish /* T9 */)))
    }

    func showReading() {
        cards.forEach { set($0, value: "—", note: plain(Self.reading)) }
    }

    private func set(_ card: Card, value: String, note: NSAttributedString) {
        ObservatoryText.setText(card.value, value)
        card.note.attributedStringValue = note
        card.view.setAccessibilityLabel(value)
        card.view.setAccessibilityValue(note.string)
    }

    private func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: theme.interfaceFont(size: theme.observatory.noteSize),
                .foregroundColor: theme.text.secondary.nsColor,
            ])
    }

    /// "2 trabajando" in green and "1 esperando" in amber, as the board colours them.
    private func sessionsNote(_ summary: ObservatoryReport.Summary) -> NSAttributedString {
        let text = ObservatoryTexts.sessions(summary, copy: .spanish /* T9 */)
        let note = NSMutableAttributedString(attributedString: plain(text))
        let tones: [(String, RGBAColor)] = [
            ("\(summary.working) trabajando", theme.agent.working),
            ("\(summary.waiting) esperando", theme.agent.waiting),
            ("\(summary.failed) error", theme.agent.failed),
        ]
        for (part, color) in tones {
            let range = (text as NSString).range(of: part)
            if range.location != NSNotFound { note.addAttribute(.foregroundColor, value: color.nsColor, range: range) }
        }
        return note
    }
}
