/// Commands the project itself offers: `npm run` scripts, `make` targets and switching to another local branch.
/// They weigh little, so history wins as soon as there is any.
public struct ProjectCommands: PredictionRule {
    public static let weight = 0.5
    public let worksOnEmptyLine = false

    public init() {}

    public func candidates(_ context: PredictionContext) -> [Candidate] {
        let project = context.project
        let otherBranches = project.branches.filter { $0 != project.branch }
        let commands =
            project.scripts.map { "npm run \($0)" } + project.makeTargets.map { "make \($0)" }
            + otherBranches.flatMap { ["git checkout \($0)", "git switch \($0)"] }
        return commands.map { Candidate(command: $0, score: Self.weight) }
    }
}
