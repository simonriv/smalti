import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Project discovery (F8.5)")
struct ProjectDiscoveryTests {
    private let home = "/Users/ana"

    private func discovery(layouts: Set<String>, repositories: Set<String> = []) -> (
        ProjectDiscovery, InMemoryProjectFiles
    ) {
        let files = InMemoryProjectFiles(layoutRoots: layouts, repositoryRoots: repositories)
        return (ProjectDiscovery(files: files, home: home), files)
    }

    @Test func findsTheFileInTheFolderItself() {
        let (discovery, _) = discovery(layouts: ["/Users/ana/dev/rizaria"])

        #expect(discovery.root(containing: "/Users/ana/dev/rizaria") == "/Users/ana/dev/rizaria")
    }

    @Test func climbsToAParent() {
        let (discovery, _) = discovery(layouts: ["/Users/ana/dev/rizaria"], repositories: ["/Users/ana/dev/rizaria"])

        #expect(discovery.root(containing: "/Users/ana/dev/rizaria/web/src") == "/Users/ana/dev/rizaria")
    }

    @Test func theNearestWinsInAMonorepo() {
        let (discovery, _) = discovery(
            layouts: ["/Users/ana/dev/mono", "/Users/ana/dev/mono/packages/api"], repositories: ["/Users/ana/dev/mono"])

        #expect(
            discovery.root(containing: "/Users/ana/dev/mono/packages/api/src") == "/Users/ana/dev/mono/packages/api")
        #expect(discovery.root(containing: "/Users/ana/dev/mono/packages/web") == "/Users/ana/dev/mono")
    }

    @Test func aRepositoryRootStopsTheClimb() {
        // A submodule: its `.git` file stops the search before the parent repo's layout.
        let (discovery, _) = discovery(
            layouts: ["/Users/ana/dev/app"], repositories: ["/Users/ana/dev/app", "/Users/ana/dev/app/vendor/lib"])

        #expect(discovery.root(containing: "/Users/ana/dev/app/vendor/lib/src") == nil)
    }

    @Test func theRepositoryRootItselfIsLookedAt() {
        let (discovery, _) = discovery(layouts: ["/Users/ana/dev/app"], repositories: ["/Users/ana/dev/app"])

        #expect(discovery.root(containing: "/Users/ana/dev/app") == "/Users/ana/dev/app")
    }

    @Test func neverLooksAtTheHomeNorTheDiskRoot() {
        let (discovery, files) = discovery(layouts: ["/Users/ana", "/"])

        #expect(discovery.root(containing: "/Users/ana/notes") == nil)
        #expect(discovery.root(containing: "/Users/ana") == nil)
        #expect(discovery.root(containing: "/tmp/x") == nil)
        #expect(!files.looked.contains("/Users/ana"))
        #expect(!files.looked.contains("/"))
    }

    @Test func outsideTheHomeClimbsUntilTheDiskRoot() {
        let (discovery, _) = discovery(layouts: ["/private/tmp/repo"])

        #expect(discovery.root(containing: "/private/tmp/repo/a/b") == "/private/tmp/repo")
    }

    @Test func aTrailingSlashIsTheSameFolder() {
        let (discovery, _) = discovery(layouts: ["/Users/ana/dev/rizaria"])

        #expect(discovery.root(containing: "/Users/ana/dev/rizaria/") == "/Users/ana/dev/rizaria")
    }

    @Test func climbsAtMostThirtyTwoLevels() {
        let deep = "/v" + String(repeating: "/d", count: 40)
        let (discovery, files) = discovery(layouts: ["/v"])

        #expect(discovery.root(containing: deep) == nil)
        #expect(files.looked.count == ProjectDiscovery.maximumLevels)
    }

    @Test func aRelativeDirectoryFindsNothing() {
        let (discovery, files) = discovery(layouts: ["dev"])

        #expect(discovery.root(containing: "dev") == nil)
        #expect(files.looked.isEmpty)
    }

    @Test func aHomeWrittenWithATrailingSlashIsStillNeverLookedAt() {
        let files = InMemoryProjectFiles(layoutRoots: ["/Users/ana"])
        let discovery = ProjectDiscovery(files: files, home: "/Users/ana/")

        #expect(discovery.root(containing: "/Users/ana/notes") == nil)
        #expect(!files.looked.contains("/Users/ana"))
    }
}
