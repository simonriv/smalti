import SmaltiCore
import Testing

@Suite("StopPolicy")
struct StopPolicyTests {
    private typealias F = ProcessFixtures
    private let policy = StopPolicy(ownPID: 500)
    private let pane = PaneID()

    private func verdict(_ record: ProcessRecord, roots: [ProcessRecord] = []) -> StopVerdict {
        let attribution = PaneAttribution(
            records: roots + [record], foregroundGroups: roots.isEmpty ? [:] : [pane: roots[0].pid])
        return policy.verdict(for: record, attribution: attribution)
    }

    @Test func ownUserProcessIsAllowed() {
        #expect(verdict(F.record(900, executable: "/opt/homebrew/bin/node")) == .allowed)
    }

    @Test func otherUserIsProtected() {
        #expect(verdict(F.record(900, isOwn: false, executable: "/opt/homebrew/bin/node")) == .protected(.otherUser))
    }

    @Test(arguments: [Int32(0), 1])
    func kernelAndLaunchdAreSystem(pid: Int32) {
        #expect(verdict(F.record(pid, parent: 0)) == .protected(.system))
    }

    @Test(arguments: [
        "/System/Library/CoreServices/WindowServer", "/usr/libexec/rapportd", "/usr/sbin/cfprefsd", "/sbin/launchd",
        "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect",
    ])
    func systemPathsAreProtected(path: String) {
        #expect(verdict(F.record(900, executable: path)) == .protected(.system))
    }

    @Test func userBinIsNotSystem() {
        #expect(verdict(F.record(900, executable: "/usr/bin/python3")) == .allowed)
    }

    @Test func smaltiItselfIsProtected() {
        #expect(verdict(F.record(500, executable: "/tmp/Whatever")) == .protected(.smalti))
    }

    @Test(arguments: [
        "/Applications/Smalti.app/Contents/MacOS/Smalti", "/tmp/build/Smalti Dev.app/Contents/MacOS/Smalti Dev",
    ])
    func otherSmaltiInstancesAreProtected(path: String) {
        #expect(verdict(F.record(900, executable: path)) == .protected(.smalti))
    }

    @Test func paneShellIsProtected() {
        let shell = F.record(102, parent: 101, name: "zsh", terminal: 7)
        let login = F.record(101, parent: 500, name: "login", isOwn: false, terminal: 7)

        #expect(verdict(shell, roots: [login]) == .protected(.paneShell))
    }

    @Test func childOfPaneShellIsAllowed() {
        let login = F.record(101, parent: 500, name: "login", isOwn: false, terminal: 7)
        let shell = F.record(102, parent: 101, name: "zsh", terminal: 7)
        let node = F.record(103, parent: 102, name: "node", terminal: 7)

        #expect(verdict(node, roots: [login, shell]) == .allowed)
    }

    @Test func zombieIsProtected() {
        #expect(verdict(F.record(900, run: .zombie)) == .protected(.zombie))
    }

    @Test func otherUserWinsOverSystem() {
        #expect(verdict(F.record(1, parent: 0, isOwn: false)) == .protected(.otherUser))
    }

    @Test func allowedVerdictSaysSo() {
        #expect(StopVerdict.allowed.isAllowed)
        #expect(!StopVerdict.protected(.zombie).isAllowed)
    }
}
