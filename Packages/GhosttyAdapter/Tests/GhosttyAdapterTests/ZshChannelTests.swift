import Foundation
import Testing

/// F4 T11 (spec C5, C6): the zsh side of the input channel, in a real interactive zsh with ZLE.
@Suite("zsh input channel", .serialized)
struct ZshChannelTests {
    /// A server that suggests `tatus` after `git s` and `ommit -m` after `git c`, echoing the line's seq.
    private static func suggesting(_ fields: [String]) -> [String] {
        guard fields.first == "line", fields.count >= 4 else { return [] }
        switch fields[3] {
        case "git s": return ["suggest\t\(fields[1])\ttatus"]
        case "git c": return ["suggest\t\(fields[1])\tommit -m"]
        default: return []
        }
    }

    @Test func sendsLineWhenBufferChanges() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ls")

        #expect(server.waitFor { $0.contains("line\t2\t2\tls") })
        #expect(server.received.first?.hasPrefix("hello\t6F2B4E1C") == true)
    }

    @Test func doesNotResendUnchangedLine() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ls")
        _ = zsh.dump()
        _ = zsh.dump()

        #expect(server.received.filter { $0.hasPrefix("line") }.count == 2)
    }

    @Test func paintsGhostFromSuggest() throws {
        let server = try FakeInputServer(reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git s")
        let state = try #require(zsh.dump())

        #expect(state.ghost == "tatus")
        #expect(state.highlight.contains("fg=#5f6672 memo=smalti"))
    }

    @Test func ignoresSuggestWithOldSeq() throws {
        let server = try FakeInputServer(mode: .staleSeq, reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git s")

        #expect(zsh.dump()?.ghost == "")
    }

    @Test func ghostShrinksWhileTypingItsLetters() throws {
        let server = try FakeInputServer(reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git s")
        zsh.type("ta")

        #expect(zsh.dump()?.ghost == "tus")
    }

    @Test func rightArrowAcceptsGhostAtEnd() throws {
        let server = try FakeInputServer(reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git s")
        zsh.type("\u{1b}[C")

        #expect(zsh.dump() == ZshHarness.State(buffer: "git status", cursor: 10, ghost: "", highlight: ""))
    }

    @Test func rightArrowMovesCursorWhenNotAtEnd() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("abc\u{1b}[D\u{1b}[D")
        zsh.type("\u{1b}[C")

        #expect(zsh.dump()?.cursor == 2)
    }

    @Test func ctrlEAcceptsGhost() throws {
        let server = try FakeInputServer(reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git c")
        zsh.type("\u{05}")

        #expect(zsh.dump()?.buffer == "git commit -m")
    }

    @Test func execAndDoneCarryCommandAndExit() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("false\r", settle: 0.5)

        #expect(server.waitFor { lines in lines.contains { $0.hasPrefix("exec\t") && $0.hasSuffix("\tfalse") } })
        #expect(server.waitFor { lines in lines.contains { $0.hasPrefix("done\t") && $0.hasSuffix("\t1") } })
    }

    @Test func spaceLedCommandIsNotReportedWithHistIgnoreSpace() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path, zshrc: "setopt HIST_IGNORE_SPACE")
        defer { zsh.close() }

        zsh.type(" true\r", settle: 0.5)
        zsh.type("ls", settle: 0.3)

        #expect(!server.received.contains { $0.hasPrefix("exec") || $0.hasPrefix("done") })
    }

    @Test func nonAsciiCursorMatches() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("echo canción a👍🏽")

        let arrived = server.waitFor { $0.last?.hasSuffix("\t16\techo canción a👍🏽") == true }
        #expect(arrived, "\(server.received.suffix(3))")
    }

    @Test func hugePasteKeepsShellResponsive() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\u{1b}[200~" + String(repeating: "x", count: 20_000) + "\u{1b}[201~", settle: 1)
        zsh.type("\u{15}echo ok")

        #expect(zsh.dump()?.buffer == "echo ok")
        #expect(!server.received.contains { $0.utf8.count >= 2_000 })
    }

    // MARK: C5 — the shell never waits for Smalti nor dies because of it

    @Test func noSocketLeavesShellNormal() throws {
        let zsh = try ZshHarness(socket: "/tmp/smalti-missing-\(UUID().uuidString.prefix(8)).sock")
        defer { zsh.close() }

        zsh.type("echo ok")

        #expect(zsh.dump()?.buffer == "echo ok")
    }

    @Test func slowServerNeverBlocksTyping() throws {
        let server = try FakeInputServer(mode: .slow, reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        let started = Date()

        zsh.type("git s", settle: 0.05)
        zsh.type("tatus", settle: 0.05)
        let state = zsh.dump()

        #expect(state?.buffer == "git status")
        #expect(Date().timeIntervalSince(started) < 1.5)
    }

    @Test func serverThatNeverReadsNeverBlocks() throws {
        let server = try FakeInputServer(mode: .neverReads)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        // Each keystroke after the paste sends a ~1500-byte line: the socket buffer fills after a few.
        zsh.type("\u{1b}[200~" + String(repeating: "x", count: 1_500) + "\u{1b}[201~", settle: 0.3)
        for _ in 0..<20 { zsh.type("y", settle: 0.02) }
        zsh.type("\u{15}echo ok")

        #expect(zsh.dump()?.buffer == "echo ok")
    }

    /// Lines between the socket's 2048-byte low-water mark and 4096 bytes could block even after `zselect -w`.
    @Test func linesOverTheLowWaterMarkNeverBlock() throws {
        let server = try FakeInputServer(mode: .neverReads)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\u{1b}[200~" + String(repeating: "x", count: 2_500) + "\u{1b}[201~", settle: 0.3)
        for _ in 0..<20 { zsh.type("y", settle: 0.02) }
        zsh.type("\u{15}echo ok")

        #expect(zsh.dump()?.buffer == "echo ok")
    }

    @Test func serverClosingMidwayDisablesQuietly() throws {
        let server = try FakeInputServer(mode: .closesAfter(3), reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("abcdef", settle: 0.5)
        zsh.type("\u{15}echo ok")

        #expect(zsh.isRunning)
        #expect(zsh.dump() == ZshHarness.State(buffer: "echo ok", cursor: 7, ghost: "", highlight: ""))
    }

    @Test func afterDisableChildrenKeepDefaultSigpipe() throws {
        let server = try FakeInputServer(mode: .closesAfter(2))
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("abc", settle: 0.5)

        // 141 = killed by SIGPIPE; a child that inherited an ignored SIGPIPE would exit 1 with "Broken pipe".
        zsh.type("\u{15}yes | head -1 > /dev/null; print -r -- PIPE=${pipestatus[1]}\r", settle: 1)

        #expect(zsh.printed.contains("PIPE=141"))
    }
}
