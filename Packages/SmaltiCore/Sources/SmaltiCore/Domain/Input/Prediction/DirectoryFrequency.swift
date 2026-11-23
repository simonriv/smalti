import Foundation

/// Commands used often and lately, here first: `uses × 0.5^(age / halfLife)`, with uses in other directories at
/// a quarter of their weight. Age is that of the command's last use.
public struct DirectoryFrequency: PredictionRule {
    public static let otherDirectoryWeight = 0.25
    public let halfLife: TimeInterval
    public let worksOnEmptyLine = false

    public init(halfLife: TimeInterval = 7 * 86_400) {
        self.halfLife = halfLife
    }

    public func candidates(_ context: PredictionContext) -> [Candidate] {
        context.index.commands(in: nil).map { stats in
            let weightedUses = stats.usesByDirectory.reduce(0.0) { total, entry in
                total + Double(entry.value) * (entry.key == context.directory ? 1 : Self.otherDirectoryWeight)
            }
            let age = max(context.now.timeIntervalSince(stats.lastUsed), 0)
            return Candidate(command: stats.command, score: weightedUses * pow(0.5, age / halfLife))
        }
    }
}
