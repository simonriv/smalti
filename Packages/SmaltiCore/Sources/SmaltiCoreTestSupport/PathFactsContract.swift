import SmaltiCore
import Testing

/// The same five paths for every `PathFacts`: a file, a folder, a missing path, a link to the file and a link to
/// that link (one level is followed, two are not).
public struct PathFactsSample: Sendable {
    public let file: String
    public let directory: String
    public let missing: String
    public let linkToFile: String
    public let linkToLink: String

    public init(file: String, directory: String, missing: String, linkToFile: String, linkToLink: String) {
        self.file = file
        self.directory = directory
        self.missing = missing
        self.linkToFile = linkToFile
        self.linkToLink = linkToLink
    }

    /// The sample's paths under `root`, as the real adapter's test creates them.
    public static func standard(root: String) -> PathFactsSample {
        PathFactsSample(
            file: root + "/file.txt", directory: root + "/folder", missing: root + "/missing",
            linkToFile: root + "/link", linkToLink: root + "/link-to-link")
    }

    /// What an in-memory fake must answer for the sample.
    public var kinds: [String: PathKind] {
        [file: .file, directory: .directory, linkToFile: .file]
    }
}

public enum PathFactsContract {
    public static func verify(_ make: () async throws -> (any PathFacts, PathFactsSample)) async throws {
        let (facts, sample) = try await make()
        #expect(await facts.kind(of: sample.file) == .file)
        #expect(await facts.kind(of: sample.directory) == .directory)
        #expect(await facts.kind(of: sample.missing) == nil)
        #expect(await facts.kind(of: sample.linkToFile) == .file)
        #expect(await facts.kind(of: sample.linkToLink) == nil)
    }
}
