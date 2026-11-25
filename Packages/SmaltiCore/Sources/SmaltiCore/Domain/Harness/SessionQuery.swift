import Foundation

/// What the session search asks for: a harness (or all), typed text and, for capture, a directory.
public struct SessionQuery: Equatable, Sendable {
    public static let defaultLimit = 200

    public var harness: HarnessID?
    public var text: String
    public var directory: String?
    public var limit: Int

    public init(harness: HarnessID? = nil, text: String = "", directory: String? = nil, limit: Int = defaultLimit) {
        self.harness = harness
        self.text = text
        self.directory = directory
        self.limit = limit
    }

    /// Text matches the title or the project fuzzily, like ⌘K (F1).
    public func matches(_ session: HarnessSession) -> Bool {
        if let harness, harness != session.harness { return false }
        if let directory, !ResolvedPath.same(directory, session.directory) { return false }
        guard !text.isEmpty else { return true }
        return fuzzyScore(text, in: session.title) != nil || fuzzyScore(text, in: session.project) != nil
    }
}

/// Paths as macOS resolves them: `/tmp` and `/var` are links into `/private`, and a final slash means nothing.
public enum ResolvedPath {
    private static let linkedRoots = ["/private/tmp", "/private/var"]

    public static func same(_ first: String, _ second: String) -> Bool {
        normalized(first) == normalized(second)
    }

    public static func normalized(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        for root in linkedRoots where result == root || result.hasPrefix(root + "/") {
            result.removeFirst("/private".count)
        }
        return result
    }
}
