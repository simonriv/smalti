import Foundation
import Testing

/// F4 T11 (spec C5, C6): the zsh side of the input channel, in a real interactive zsh with ZLE.
@Suite("zsh input channel", .serialized)
struct ZshChannelTests {
    /// A server that suggests `tatus` after `git s` and `ommit -m` after `git c`, echoing the line's seq.
    private static func suggesting(_ fields: [String]) -> [String] {
        guard fields.first == "line", fields.count >= 4 else { return [] }
        switch fields.last ?? "" {
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

        #expect(server.waitFor { $0.contains { $0.hasPrefix("line\t2\t") && $0.hasSuffix("\t2\tls") } })
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

    // MARK: Block 3 review

    /// C1: turning the channel off must not take the shell's stderr with it.
    @Test func stderrSurvivesDisabling() throws {
        let server = try FakeInputServer(mode: .closesAfter(2))
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("abc", settle: 0.5)

        zsh.type("\u{15}ls /smalti-missing-path\r", settle: 0.6)

        #expect(zsh.printed.contains("smalti-missing-path"))
        #expect(zsh.printed.contains("No such file"))
    }

    /// C2: an answer without its newline never freezes the line editor.
    @Test func partialAnswerNeverFreezesTyping() throws {
        let server = try FakeInputServer { fields in
            fields.first == "line" && fields.last == "ec" ? ["RAW:suggest\t\(fields[1])\tho hi"] : []
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ec", settle: 0.4)
        zsh.type("ho ok")

        #expect(zsh.dump()?.buffer == "echo ok")
    }

    /// I1: the user's options never break the channel nor the shell.
    @Test(arguments: ["nounset", "errexit", "shwordsplit", "extendedglob globsubst", "ksharrays", "errreturn"])
    func userOptionsDoNotBreakTheChannel(options: String) throws {
        let server = try FakeInputServer(reply: Self.suggesting)
        let zsh = try ZshHarness(socket: server.path, zshrc: "setopt \(options)")
        defer { zsh.close() }

        zsh.type("echo ab\r", settle: 0.5)
        zsh.type("git s")
        zsh.type("\u{1b}[C")

        #expect(zsh.isRunning)
        #expect(server.waitFor { $0.contains { $0.hasPrefix("exec\t") && $0.hasSuffix("\techo ab") } })
        #expect(zsh.dump()?.buffer == "git status")
        #expect(!zsh.printed.contains("parameter not set"))
        #expect(!zsh.printed.contains("bad pattern"))
    }

    /// I2: the socket lives on a descriptor of ten or more, so `exec 3>file` never receives Smalti's messages.
    @Test func socketAvoidsTheLowDescriptors() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        let file = zsh.work.appending(path: "three").path(percentEncoded: false)

        zsh.type("exec 3>\(file)\r", settle: 0.4)
        zsh.type("true\r", settle: 0.6)

        #expect(((try? String(contentsOfFile: file, encoding: .utf8)) ?? "").isEmpty)
        #expect(server.waitFor { $0.contains { $0.hasPrefix("exec\t") && $0.hasSuffix("\ttrue") } })
    }

    /// I2: the shell says goodbye on exit, so Smalti forgets it even if a background child keeps the socket.
    @Test func exitSendsBye() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("exit\r", settle: 0.6)

        #expect(server.waitFor { $0.last == "bye" })
    }

    /// I5: a line too long to send still makes earlier answers stale.
    @Test func overLongLineDiscardsTheLateSuggestion() throws {
        let server = try FakeInputServer(mode: .slow) { fields in
            fields.first == "line" && fields.last == "git st" ? ["suggest\t\(fields[1])\tatus"] : []
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git st", settle: 0.1)
        zsh.type("\u{1b}[200~" + String(repeating: "x", count: 2_500) + "\u{1b}[201~", settle: 2.5)

        #expect(zsh.dump()?.ghost == "")
    }

    /// Minor: numeric fields are checked before zsh evaluates them.
    @Test func answerFieldsAreNeverEvaluated() throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "smalti-injected-\(UUID())")
        let path = marker.path(percentEncoded: false)
        let server = try FakeInputServer { fields in
            fields.first == "line" ? ["suggest\ta[$(touch \(path))1]\tx"] : []
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ls", settle: 0.5)

        #expect(!FileManager.default.fileExists(atPath: path))
    }

    /// Minor: `vared` and `select` are not the prompt; their text never reaches Smalti.
    @Test func varedIsNotReported() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("vared -c -p 'secret: ' v\r", settle: 0.5)
        zsh.type("hunter2", settle: 0.4)

        #expect(!server.received.contains { $0.contains("hunter2") }, "\(server.received.prefix(24).suffix(8))")
    }

    /// Block 4 review I4: every line names the shell's directory, so a `cd` never races the terminal's OSC 7.
    @Test func linesCarryTheShellsDirectory() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("cd /tmp\r", settle: 0.5)
        zsh.type("ls")

        #expect(server.waitFor { $0.contains { $0.hasPrefix("line\t") && $0.hasSuffix("\t/tmp\t2\tls") } })
        #expect(server.waitFor { $0.contains { $0.hasPrefix("exec\t") && $0.hasSuffix("\tcd /tmp") } })
    }
}
