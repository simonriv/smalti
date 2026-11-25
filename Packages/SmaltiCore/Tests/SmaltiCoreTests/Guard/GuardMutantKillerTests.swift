import Foundation
import SmaltiCoreTestSupport
import Testing

@testable import SmaltiCore

/// Pins the F7.5 behaviour that the review 1 mutation run showed no other test fixed. Each test names the mutant it
/// kills; all were checked by applying the mutant by hand.
@MainActor
@Suite("Guard edge cases found by mutation testing")
struct GuardMutantKillerTests {
    private let home = "/Users/u"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func commands(_ text: String) -> [SimpleCommand] {
        ShellCommandLine.commands(in: text, home: home)
    }

    private func verdict(_ command: String) -> GuardVerdict {
        ScreenToolUse.verdict(
            for: ToolUse(tool: "Bash", command: command, cwd: "/p"),
            context: GuardContext(settings: .standard, environmentHosts: []), home: home)
    }

    // MARK: - AgentApprovals: a denial is never reported as approved

    final class Changes {
        var items: [AgentApprovalChange] = []
        var approvedFlags: [Bool] {
            items.compactMap { change in
                if case .settled(_, let approved, _) = change { return approved }
                return nil
            }
        }
    }

    private func queue(_ changes: Changes, panes: [PaneID]) -> AgentApprovals {
        let approvals = AgentApprovals(home: home)
        approvals.onChange = { changes.items.append($0) }
        for pane in panes {
            let use = ToolUse(tool: "Bash", command: "terraform destroy", cwd: "/p")
            approvals.receive(
                GuardRequest(
                    id: UUID(), pane: pane, use: use, environmentHosts: [],
                    localVerdict: .ask(ApprovalSubject(command: "", findings: [])), receivedAt: t0, reply: { _ in }))
        }
        return approvals
    }

    @Test func rejectionIsReportedAsNotApproved() {
        let changes = Changes()
        let approvals = queue(changes, panes: [PaneID()])

        approvals.reject(approvals.allPending[0].id)

        #expect(changes.approvedFlags == [false])
    }

    @Test func closedPaneIsReportedAsNotApproved() {
        let changes = Changes()
        let pane = PaneID()
        let approvals = queue(changes, panes: [pane])

        approvals.paneClosed(pane)

        #expect(changes.approvedFlags == [false])
    }

    @Test func retainedAwayIsReportedAsNotApproved() {
        let changes = Changes()
        let approvals = queue(changes, panes: [PaneID()])

        approvals.retain([])

        #expect(changes.approvedFlags == [false])
    }

    @Test func stopIsReportedAsNotApproved() {
        let changes = Changes()
        let approvals = queue(changes, panes: [PaneID()])

        approvals.stop()

        #expect(changes.approvedFlags == [false])
    }

    @Test func expiryIsReportedAsNotApproved() {
        let changes = Changes()
        let approvals = queue(changes, panes: [PaneID()])

        approvals.expire(now: t0.addingTimeInterval(AgentApprovals.standardTimeout))

        #expect(changes.approvedFlags == [false])
    }

    // MARK: - Review 2 mutation survivors

    @Test func wgetMethodWithoutValue() {
        #expect(guardFindings("wget https://api.heroku.com/apps/x --method").isEmpty)
    }

    @Test func rootFolderIsNotASecret() {
        #expect(!SecretPaths(home: home).isSecret("/", cwd: nil))
    }

    @Test func lonelyRedirectionStillReadsTheSecret() {
        #expect(verdict("< .env").isDenied)
    }

    // MARK: - CommandCatalog: approval and secret entries are never "current"

    @Test func guardEntriesAreNotCurrent() throws {
        let root = try WorkingDirectory(path: "/tmp/p")
        let pane = PaneID()
        let set = WorkspaceSet(
            first: Workspace.empty(name: "w", rootDirectory: root, layout: DwindleLayout())
                .adding(Pane(id: pane, workingDirectory: root)))
        let approval = PendingApproval(
            id: UUID(), pane: pane,
            subject: ApprovalSubject(command: "x", findings: [GuardFinding(rule: "x", environment: .undetermined)]),
            since: t0, deadline: t0)
        let state = CatalogState(
            workspaces: set, pendingApprovals: [ApprovalEntry(approval: approval, workspace: "w")],
            secretsProject: SecretsProjectState(name: "p", isProtected: false))

        let entries = CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard).filter {
            $0.group == .approvals || $0.id == .secretsProtect
        }

        #expect(entries.count == 3)
        #expect(entries.allSatisfy { !$0.isCurrent })
    }

    // MARK: - DatabaseURL and HostPattern

    @Test func schemeKeepsItsDashes() {
        #expect(DatabaseURL.hosts(in: "foo-postgres://h/db").isEmpty)
    }

    @Test func emptyFirstHostOfAListIsLocal() {
        #expect(DatabaseURL.hosts(in: "postgres://,b.x.com/db") == [""])
    }

    @Test func emptyHostLabelsDoNotMatch() {
        #expect(!HostPattern.matches("db.x.com", "db..x.com"))
    }

    // MARK: - GlobPattern

    @Test func starBacktracksFromWhereItStarted() {
        #expect(!GlobPattern.matches("ab*bx", "abx"))
    }

    @Test func literalMismatchFails() {
        #expect(!GlobPattern.matches("abc", "abd"))
    }

    @Test func bracketSetIsOneCharacter() {
        #expect(GlobPattern.matches("[ab]c", "ac"))
        #expect(GlobPattern.matches("[ab]", "a"))
        #expect(!GlobPattern.matches("[ab]", "c"))
    }

    @Test func negatedSets() {
        #expect(GlobPattern.matches("[!a]", "b"))
        #expect(!GlobPattern.matches("[!a]", "a"))
        #expect(GlobPattern.matches("[^a]", "b"))
    }

    @Test func closingBracketFirstIsLiteral() {
        #expect(GlobPattern.matches("[]a]", "]"))
    }

    @Test func ranges() {
        #expect(GlobPattern.matches("[a-c]", "b"))
        #expect(!GlobPattern.matches("[a-c]", "d"))
        #expect(!GlobPattern.matches("[a-c]", "-"))
        #expect(GlobPattern.matches("[ac-]", "-"))
    }

    // MARK: - SQL clients

    @Test func attachedShortOptionShowsTheSQL() {
        #expect(guardFindings("psql -cselect").isEmpty)
    }

    @Test func hostOptionAtTheEndHasNoValue() {
        #expect(guardFindings("psql -c 'drop table a' -h").first?.environment == .undetermined)
    }

    @Test func keywordAtTheEndOfTheText() {
        #expect(guardFindings("psql -c drop").first?.rule == "psql con DROP")
    }

    @Test func keywordInsideAWordIsNotAKeyword() {
        #expect(guardFindings("psql -c 'select dropx'").isEmpty)
    }

    // MARK: - curl, wget and HTTPie

    @Test(arguments: [
        "curl --get -d a=1 https://api.vercel.com/x", "curl --head -d x https://api.vercel.com/x",
        "curl -I -d x https://api.vercel.com/x", "curl --output -d https://api.vercel.com/x",
        "curl --data=x -X GET https://api.vercel.com/x", "http api.planetscale.com/v1/x foo",
    ])
    func readOnlyRequestsPass(command: String) {
        #expect(guardFindings(command).isEmpty)
    }

    @Test func uploadFileIsAPut() {
        #expect(guardFindings("curl --upload-file f https://s3.amazonaws.com/b").map(\.rule) == ["API de AWS (PUT)"])
    }

    @Test func wgetMethodWithSpace() {
        #expect(
            guardFindings("wget --method DELETE https://api.heroku.com/apps/x").map(\.rule) == [
                "API de Heroku (DELETE)"
            ])
    }

    // MARK: - SecretPaths

    @Test func homeWithTrailingSlash() {
        #expect(SecretPaths(home: "/Users/u/").isSecret("/Users/u/.ssh/config", cwd: nil))
    }

    @Test func codeOptionWithoutCode() {
        #expect(verdict("python3 -c") == .allow)
    }

    @Test func envFileSkipsOnlyItsValue() {
        #expect(verdict("node --env-file .env app.js .env.local").isDenied)
    }

    // MARK: - ShellCommandLine

    @Test func assignmentNamesStartWithALetterOrUnderscore() {
        #expect(commands("1A=x terraform destroy").first?.program == "1A=x")
    }

    @Test func onlyAnOptionWithCIsTheShellScript() {
        #expect(guardFindings("bash script.sh 'terraform destroy'").isEmpty)
    }

    @Test func shellCAtTheEnd() {
        #expect(commands("bash -c").map(\.program) == ["bash"])
    }

    @Test func everyOptionBeforeTheProgramIsSkipped() {
        #expect(commands("sudo -E -H terraform destroy").first?.program == "terraform")
    }

    // MARK: - ShellLexer

    @Test func tildeInsideAWordIsLiteral() {
        #expect(commands("echo a~/x").first?.arguments == ["a~/x"])
    }

    @Test func onlyOneWordFollowsARedirection() {
        let command = commands("cat < in out").first

        #expect(command?.redirections == ["in"])
        #expect(command?.arguments == ["out"])
    }

    @Test func nextSegmentStartsAfterTheSeparator() {
        #expect(commands("a; b").last?.rawText == "b")
        #expect(commands("ls\t; b").first?.rawText == "ls")
    }

    @Test func dangingRedirectionEndsWithItsSegment() {
        #expect(commands("cat < ; ls").last?.program == "ls")
    }

    @Test func duplicationAtTheEndHasNoFile() {
        #expect(commands("echo >&").first?.redirections == [])
    }

    @Test func heredocIsReadOnce() {
        let programs = commands("cat <<A\nx\nA\nls\nterraform destroy\n").compactMap(\.program)

        #expect(programs == ["cat", "ls", "terraform"])
    }

    @Test func unclosedHeredocAtTheEnd() {
        #expect(commands("cat <<A\nx").first?.heredocs == ["x"])
    }

    @Test func commandAfterAHeredocHasItsOwnText() {
        #expect(commands("cat <<A\nx\nA\nls").last?.rawText == "ls")
    }

    @Test func duplicationNeedsADescriptor() {
        #expect(commands("cmd >&out.txt").first?.redirections == ["out.txt"])
    }

    @Test func backslashEscapesTheNextCharacter() {
        #expect(commands(#"echo a\b"#).first?.arguments == ["ab"])
    }

    @Test func backslashEscapesInsideDoubleQuotes() {
        #expect(commands(#"echo "a\$b""#).first?.arguments == ["a$b"])
    }

    @Test func ansiCQuoteIsLiteralInsideDoubleQuotes() {
        #expect(commands("echo \"$'.env'\"").first?.arguments == ["$'.env'"])
    }

    @Test func commentEndsTheLine() {
        #expect(commands("ls # cat .env").first?.arguments == [])
    }

    @Test(arguments: [
        ("echo ~root", ["~root"]), ("echo ~ x", ["/Users/u", "x"]), ("echo ~\tx", ["/Users/u", "x"]),
    ])
    func tildeExpandsOnlyAlone(text: String, arguments: [String]) {
        #expect(commands(text).first?.arguments == arguments)
    }

    @Test func tildeBeforeANewline() {
        #expect(commands("echo ~\nls").first?.arguments == ["/Users/u"])
    }

    @Test func numericEscapes() {
        #expect(commands(#"echo $'\x41' $'\101'"#).first?.arguments == ["A", "A"])
    }

    @Test func substitutionCountsNestedParentheses() {
        #expect(ShellLexer.segments(of: "echo $(a (b) c)", home: home).first?.substitutions == ["a (b) c"])
    }

    @Test func homeVariableNeedsTheWholeName() {
        #expect(commands("echo $HOMEx").first?.arguments == ["$HOMEx"])
        #expect(commands("echo $HOME1").first?.arguments == ["$HOME1"])
        #expect(commands("echo $HOME").first?.arguments == ["/Users/u"])
    }
}
