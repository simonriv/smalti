/// Finds credentials in a command line: what stays out of Smalti's history (F4) and of any API request (F7).
///
/// `\b` uses simple word boundaries: with Unicode's default, `:` between letters does not break a word
/// (`X-Token:eyJ…`). It looks for values, not words: `cat token_list.txt` is clean, `FOO_TOKEN=x` is not. Each pattern names the
/// part to hide; redaction keeps the key so the line still reads (`OPENAI_API_KEY=«redactado»`).
public enum SecretFilter {
    public static let mask = "«redactado»"

    public static func isSensitive(_ command: String) -> Bool {
        patterns.contains { command.contains($0.regex) }
    }

    public static func redacted(_ text: String) -> String {
        patterns.reduce(text) { partial, pattern in
            partial.replacing(pattern.regex) { match in pattern.keep(String(match.output)) + mask }
        }
    }

    private struct Pattern {
        let regex: Regex<Substring>
        /// The leading part of a match that stays visible (the key name, the URL user).
        let keep: (String) -> String
    }

    /// Built on each call: `Regex` is not `Sendable`, so it cannot live in a static constant under strict concurrency.
    private static var patterns: [Pattern] {
        [
            Pattern(
                regex: /\b[A-Za-z0-9_]*(?:_KEY|_TOKEN|_SECRET|PASSWORD|_PASSWD)=(?:"[^"]*"|'[^']*'|[^\s"']+)/
                    .ignoresCase().wordBoundaryKind(.simple),
                keep: { prefix(of: $0, through: "=") }),
            Pattern(
                regex: /Authorization:\s*(?:[A-Za-z]+\s+)?[^\s"']+/.ignoresCase().wordBoundaryKind(.simple),
                keep: { prefix(of: $0, through: ":") + " " }),
            Pattern(regex: /\bsk-[A-Za-z0-9_-]{16,}/.wordBoundaryKind(.simple), keep: { _ in "" }),
            Pattern(regex: /\bghp_[A-Za-z0-9]{20,}/.wordBoundaryKind(.simple), keep: { _ in "" }),
            Pattern(regex: /\bgithub_pat_[A-Za-z0-9_]{20,}/.wordBoundaryKind(.simple), keep: { _ in "" }),
            Pattern(regex: /\bxox[abposr]-[A-Za-z0-9-]{10,}/.wordBoundaryKind(.simple), keep: { _ in "" }),
            Pattern(regex: /\bAKIA[0-9A-Z]{16}/.wordBoundaryKind(.simple), keep: { _ in "" }),
            Pattern(
                regex: /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/.wordBoundaryKind(.simple),
                keep: { _ in "" }),
            Pattern(
                regex: /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\s\/:@]+:[^\s\/@]+(?=@)/.wordBoundaryKind(.simple),
                keep: { prefix(of: $0, throughLast: ":") }),
        ]
    }

    private static func prefix(of text: String, through separator: Character) -> String {
        guard let index = text.firstIndex(of: separator) else { return "" }
        return String(text[...index])
    }

    private static func prefix(of text: String, throughLast separator: Character) -> String {
        guard let index = text.lastIndex(of: separator) else { return "" }
        return String(text[...index])
    }
}
