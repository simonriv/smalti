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
/// nothing with the cursor inside the line, and breaks ties by the command's last use, then alphabetically.
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
            .max { lhs, rhs in
                let (left, right) = (rank(lhs, in: context.index), rank(rhs, in: context.index))
                return left != right ? left < right : lhs.key > rhs.key
            }
        return best.map { Prediction(suffix: String($0.key.dropFirst(typed.count))) }
    }

    private func rank(_ total: (key: String, value: Double), in index: HistoryIndex) -> Rank {
        Rank(score: total.value, lastUsed: index.stats(for: total.key)?.lastUsed ?? .distantPast)
    }

    private struct Rank: Comparable {
        let score: Double
        let lastUsed: Date

        static func < (lhs: Rank, rhs: Rank) -> Bool { (lhs.score, lhs.lastUsed) < (rhs.score, rhs.lastUsed) }
    }
}
