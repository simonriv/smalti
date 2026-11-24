/// "Solo símbolo · contexto en la cabecera" (spec F5): the segments as one line for the pane header, the directory
/// trimmed from the left by whole levels when it does not fit.
public enum PromptHeaderText {
    private static let separator = " · "
    private static let ellipsis = "…"

    public static func text(for segments: [PromptSegment], maxWidth: Int) -> String {
        let full = joined(segments.map(\.text), segments)
        guard full.count > maxWidth else { return full }
        if let directory = segments.firstIndex(where: { $0.module == .directory }) {
            var texts = segments.map(\.text)
            let levels = texts[directory].split(separator: "/").map(String.init)
            for kept in stride(from: levels.count - 1, through: 1, by: -1) {
                texts[directory] = ellipsis + "/" + levels.suffix(kept).joined(separator: "/")
                let candidate = joined(texts, segments)
                if candidate.count <= maxWidth { return candidate }
            }
        }
        return String(full.prefix(max(0, maxWidth - 1))) + ellipsis
    }

    /// Like the prompt line: git changes stay next to the branch.
    private static func joined(_ texts: [String], _ segments: [PromptSegment]) -> String {
        zip(texts, segments).enumerated().map { index, pair in
            guard index > 0 else { return pair.0 }
            let joinsBranch = pair.1.module == .gitStatus && segments[index - 1].module == .gitBranch
            return (joinsBranch ? " " : separator) + pair.0
        }.joined()
    }
}
