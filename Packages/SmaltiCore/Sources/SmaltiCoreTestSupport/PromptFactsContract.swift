import Foundation
import SmaltiCore
import Testing

/// Every `PromptFacts` answers a directory that does not exist with no facts, and never fails.
public enum PromptFactsContract {
    public static func verify(_ make: () async -> any PromptFacts) async {
        let facts = await make()
        let missing = PromptQuery(directory: "/nonexistent-\(UUID())", runtimePaths: [:], kubeconfig: nil)
        #expect(await facts.facts(for: missing) == .none, "a missing directory has no repository, runtime or context")
    }
}
