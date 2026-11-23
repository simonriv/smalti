/// After a failure, the fix the user ran the last times that same command failed; plus fixed rules for failures
/// whose fix is known (`git push` without an upstream → `git push -u origin <branch>`).
public struct ExitRecovery: PredictionRule {
    public static let weight = 5.0
    public static let ruleWeight = 3.0
    public let worksOnEmptyLine = true

    public init() {}

    public func candidates(_ context: PredictionContext) -> [Candidate] {
        guard let failed = context.previous, failed.hasFailed else { return [] }
        let learned = context.index.fixes(after: failed.command).map {
            Candidate(command: $0.key, score: Double($0.value) * Self.weight)
        }
        return learned + knownFixes(for: failed.command, project: context.project)
    }

    private func knownFixes(for command: String, project: ProjectSnapshot) -> [Candidate] {
        guard command == "git push", let branch = project.branch, !project.hasUpstream else { return [] }
        return [Candidate(command: "git push -u origin \(branch)", score: Self.ruleWeight)]
    }
}
