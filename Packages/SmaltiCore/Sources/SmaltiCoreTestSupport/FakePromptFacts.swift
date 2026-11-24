import SmaltiCore

/// Answers from a table by directory; any other directory has no facts.
public struct FakePromptFacts: PromptFacts {
    private let answers: [String: PromptFactsResult]

    public init(answers: [String: PromptFactsResult] = [:]) {
        self.answers = answers
    }

    public func facts(for query: PromptQuery) async -> PromptFactsResult {
        answers[query.directory] ?? .none
    }
}
