import Foundation

public struct Prediction: Equatable, Sendable {
    /// The rest of the line, drawn as ghost text after the cursor.
    public let suffix: String

    public init(suffix: String) {
        self.suffix = suffix
    }
}

/// The default `PredictionProvider`: adds up the rules' scores per command and completes what was typed with the
/// best one. It only ever extends the line (the candidate must start with exactly the typed text), suggests
/// nothing with the cursor inside the line, and breaks ties by the command's last use.
public struct HeuristicPredictor: PredictionProvider {
    public static let standardRules: [any PredictionRule] = [
        DirectoryFrequency(), LearnedSequence(), ProjectCommands(), ExitRecovery(),
    ]

    private let rules: [any PredictionRule]

    public init(rules: [any PredictionRule] = standardRules) {
        self.rules = rules
    }

    public func predict(_ context: PredictionContext) -> Prediction? {
        let typed = context.line.text
        guard context.line.isCursorAtEnd else { return nil }
        let active = typed.isEmpty ? rules.filter(\.worksOnEmptyLine) : rules
        let totals = active.flatMap { $0.candidates(context) }.reduce(into: [String: Double]()) {
            $0[$1.command, default: 0] += $1.score
        }
        let best = totals.filter { $0.key.hasPrefix(typed) && $0.key.count > typed.count }
            .max { rank($0, in: context.index) < rank($1, in: context.index) }
        return best.map { Prediction(suffix: String($0.key.dropFirst(typed.count))) }
    }

    private func rank(_ total: (key: String, value: Double), in index: HistoryIndex) -> (Double, Date) {
        (total.value, index.stats(for: total.key)?.lastUsed ?? .distantPast)
    }
}
