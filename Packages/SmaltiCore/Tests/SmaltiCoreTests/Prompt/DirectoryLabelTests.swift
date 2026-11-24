import SmaltiCore
import Testing

/// Spec F5: outside a repository the last two levels (zsh's `%2~`); inside, from the root with the repo's name.
@Suite("DirectoryLabel")
struct DirectoryLabelTests {
    private let home = "/Users/simon"

    @Test(arguments: [
        ("/Users/simon/Downloads", "~/Downloads"), ("/usr/local/bin", "local/bin"), ("/Users/simon", "~"),
        ("/usr", "/usr"), ("/", "/"), ("/Users/simon/a/b/c", "b/c"), ("/Users/simonetta/x", "simonetta/x"),
    ])
    func outsideRepoShowsLastTwoLevels(_ directory: String, _ label: String) {
        #expect(DirectoryLabel.label(directory: directory, home: home, repoRoot: nil) == label)
    }

    @Test func homeIsTilde() {
        #expect(DirectoryLabel.label(directory: home, home: home, repoRoot: nil) == "~")
    }

    @Test func insideRepoShowsFromRootWithName() {
        let label = DirectoryLabel.label(
            directory: "/Users/simon/dev/solen/apps/api", home: home, repoRoot: "/Users/simon/dev/solen")

        #expect(label == "solen/apps/api")
    }

    @Test func repoRootShowsItsName() {
        let label = DirectoryLabel.label(
            directory: "/Users/simon/dev/solen", home: home, repoRoot: "/Users/simon/dev/solen")

        #expect(label == "solen")
    }

    @Test func rootThatIsNotAnAncestorIsIgnored() {
        let label = DirectoryLabel.label(
            directory: "/Users/simon/dev/solenoid/x", home: home, repoRoot: "/Users/simon/dev/solen")

        #expect(label == "solenoid/x")
    }

    @Test func trailingSlashIsIgnored() {
        #expect(DirectoryLabel.label(directory: "/usr/local/bin/", home: home, repoRoot: nil) == "local/bin")
    }
}

@Suite("DirectoryLabel · review")
struct DirectoryLabelReviewTests {
    /// Block 2 review (M8): a repository at the root shows `/sub`, never `//sub`.
    @Test func repositoryAtRootShowsSingleSlash() {
        #expect(DirectoryLabel.label(directory: "/sub", home: "/Users/simon", repoRoot: "/") == "/sub")
        #expect(DirectoryLabel.label(directory: "/", home: "/Users/simon", repoRoot: "/") == "/")
    }
}
