import Foundation
import Testing

/// F5 T11 (spec C7–C10, C10b): the zsh side of Smalti's prompt in a real interactive zsh — immediate prompt at once,
/// full prompt when Smalti answers, never waiting, never running a name, and the user's prompt when asked.
@Suite("zsh prompt from Smalti", .serialized)
struct PromptScriptIntegrationTests {
    static let immediate = "IMM:%2v%(3V. .)%3v %1v "
    static let full = "FULL:%4v %1v "

    static func style(ghost: String = "#5f6672", immediate: String = immediate, symbol: String = "›") -> String {
        "promptstyle\t\(immediate)\t\(ghost)\t1=\(symbol)"
    }

    static func prompt(seq: String, branch: String) -> String {
        "prompt\t\(seq)\tsolen\t\(immediate)\t\(full)\t4=\(branch)\u{1f}1=›"
    }

    /// Styles at hello; answers every `context` with a full prompt carrying `branch`.
    static func answering(branch: String) -> @Sendable ([String]) -> [String] {
        { fields in
            switch fields.first {
            case "hello": [style()]
            case "context": [prompt(seq: fields[1], branch: branch)]
            default: []
            }
        }
    }

    private func contexts(_ server: FakeInputServer) -> [[String]] {
        server.received.filter { $0.hasPrefix("context\t") }.map { $0.components(separatedBy: "\t") }
    }

    @Test func promptShowsFullWhenSmaltiAnswers() throws {
        let server = try FakeInputServer(reply: Self.answering(branch: "main"))
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.5)

        #expect(zsh.dumpPrompt()?.shown == "FULL:main › ")
    }

    @Test func immediatePromptAppearsWithoutAnAnswer() throws {
        let server = try FakeInputServer { fields in fields.first == "hello" ? [Self.style()] : [] }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("cd /usr/local/bin\r", settle: 0.5)

        #expect(zsh.dumpPrompt()?.shown == "IMM:local/bin › ")
    }

    @Test func contextCarriesDirectoryExitAndEnvironment() throws {
        let server = try FakeInputServer(reply: Self.answering(branch: "main"))
        let zsh = try ZshHarness(socket: server.path, extra: ["AWS_PROFILE": "prod"])
        defer { zsh.close() }

        zsh.type("cd /tmp; false\r", settle: 0.5)

        let last = try #require(contexts(server).last)
        #expect(last.count == 8)
        #expect(last[2] == "/tmp" || last[2] == "/private/tmp")
        #expect(last[3] == "1")
        #expect(last[5] == "prod")
    }

    @Test func durationFromTwoSecondsReachesImmediatePrompt() throws {
        let server = try FakeInputServer { fields in fields.first == "hello" ? [Self.style()] : [] }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("sleep 2.1\r", settle: 2.6)

        let shown = try #require(zsh.dumpPrompt()?.shown)
        #expect(shown.hasPrefix("IMM:"))
        // A loaded machine may add a few tenths (block 3 review, M12): any "2.x s" or "3.x s" proves format and threshold.
        #expect(shown.firstMatch(of: #/IMM:\S+ [23]\.\ds › /#) != nil, "\(shown)")
    }

    @Test func silentServerDoesNotDelayPrompt() throws {
        func timeTwentyPrompts(_ socket: String?) throws -> TimeInterval {
            let zsh = try ZshHarness(socket: socket)
            defer { zsh.close() }
            let start = Date()
            for _ in 0..<20 { zsh.type("\r", settle: 0) }
            let deadline = Date().addingTimeInterval(5)
            while zsh.printed.components(separatedBy: "p% ").count < 22, Date() < deadline { usleep(2000) }
            return Date().timeIntervalSince(start)
        }
        let silent = try FakeInputServer(mode: .neverReads)

        let withChannel = try timeTwentyPrompts(silent.path)
        let without = try timeTwentyPrompts(nil)

        // C8: ± 5 ms per prompt over 20 prompts.
        #expect(withChannel - without < 0.1, "with channel \(withChannel) s, without \(without) s")
    }

    @Test func closedChannelKeepsLastImmediatePrompt() throws {
        let server = try FakeInputServer(mode: .closesAfter(2)) { fields in
            fields.first == "hello" ? [Self.style()] : []
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.4)
        zsh.type("cd /usr/local/bin\r", settle: 0.4)

        #expect(zsh.dumpPrompt()?.shown == "IMM:local/bin › ")
        #expect(zsh.isRunning)
    }

    @Test(arguments: ["", "unsetopt prompt_subst", "setopt prompt_subst"])
    func hostileBranchDoesNotRun(_ zshrc: String) throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "smalti-pwned-\(UUID())")
        let path = marker.path(percentEncoded: false)
        let server = try FakeInputServer(reply: Self.answering(branch: "$(touch \(path))`touch \(path)`%F{red}"))
        let zsh = try ZshHarness(socket: server.path, zshrc: zshrc)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.5)
        let shown = zsh.dumpPrompt()?.shown ?? ""

        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(shown.hasPrefix("FULL:$(touch"), "\(shown)")
    }

    @Test func shellSourceKeepsUserPrompt() throws {
        let server = try FakeInputServer { fields in
            switch fields.first {
            case "hello": [Self.style(immediate: "")]
            case "context": [Self.prompt(seq: fields[1], branch: "main")]
            default: []
            }
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.5)

        let raw = zsh.dumpPrompt()?.raw ?? ""
        #expect(raw.contains("p%% "))
        #expect(!raw.contains("IMM:"))
    }

    @Test func switchingToShellSourceRestoresUserPrompt() throws {
        let server = try FakeInputServer { fields in fields.first == "hello" ? [Self.style()] : [] }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("\r", settle: 0.4)

        server.push(Self.style(immediate: ""))
        zsh.type("\r", settle: 0.4)

        let raw = zsh.dumpPrompt()?.raw ?? ""
        #expect(raw.contains("p%% "))
        #expect(!raw.contains("IMM:"))
    }

    @Test func smaltiPromptWinsOverZshrcAndStarshipLikeHook() throws {
        let server = try FakeInputServer { fields in fields.first == "hello" ? [Self.style()] : [] }
        let rc = "starship_like() { PROMPT='STAR> ' }\nprecmd_functions+=(starship_like)"
        let zsh = try ZshHarness(socket: server.path, zshrc: rc)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.4)
        zsh.type("\r", settle: 0.4)
        let state = zsh.dumpPrompt()

        #expect(state?.shown.hasPrefix("IMM:") == true, "\(state?.shown ?? "")")
        // Smalti's hook right before Ghostty's, which stays last to add its OSC 133 marks.
        #expect(state?.lastPrecmd == "_smalti_prompt_precmd _ghostty_precmd")
    }

    @Test func spontaneousPromptKeepsBuffer() throws {
        let server = try FakeInputServer { fields in fields.first == "hello" ? [Self.style()] : [] }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("\r", settle: 0.4)
        let seq = try #require(contexts(server).last?[1])

        zsh.type("ls -la")
        server.push(Self.prompt(seq: seq, branch: "claude te espera"))
        zsh.type("", settle: 0.3)
        let state = zsh.dumpPrompt()

        #expect(state?.shown == "FULL:claude te espera › ")
        #expect(state?.buffer == "ls -la")
    }

    @Test func staleSpontaneousPromptIsDropped() throws {
        let server = try FakeInputServer { fields in fields.first == "hello" ? [Self.style()] : [] }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("\r", settle: 0.4)
        let old = try #require(contexts(server).last?[1])
        zsh.type("true\r", settle: 0.4)

        server.push(Self.prompt(seq: old, branch: "viejo"))
        zsh.type("", settle: 0.3)

        #expect(zsh.dumpPrompt()?.shown.hasPrefix("IMM:") == true)
    }

    @Test func badValueNamesAreIgnored() throws {
        let server = try FakeInputServer { fields in
            switch fields.first {
            case "hello": [Self.style()]
            case "context":
                ["prompt\t\(fields[1])\tx\t\(Self.immediate)\tFULL:%4v\tPATH=/nowhere\u{1f}4=ok\u{1f}99999=z\u{1f}1=›"]
            default: []
            }
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.5)

        #expect(zsh.dumpPrompt()?.shown == "FULL:ok")
        zsh.type("print -r -- $PATH >| $HOME/path\r", settle: 0.3)
        #expect(
            (try? String(contentsOf: zsh.work.appending(path: "path"), encoding: .utf8))?.hasPrefix("/usr/bin") == true)
    }

    @Test func ghostColorChangesLive() throws {
        let server = try FakeInputServer { fields in
            switch fields.first {
            case "hello": [Self.style(ghost: "#123456")]
            case "line" where fields.last == "git s": ["suggest\t\(fields[1])\ttatus"]
            default: []
            }
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git s")

        #expect(zsh.dump()?.highlight.contains("fg=#123456 memo=smalti") == true)
    }

    @Test func promptWorksWithInputDisabled() throws {
        let server = try FakeInputServer(reply: Self.answering(branch: "main"))
        let zsh = try ZshHarness(socket: server.path, extra: ["SMALTI_INPUT_FEATURES": "0"])
        defer { zsh.close() }

        zsh.type("\r", settle: 0.5)
        zsh.type("ls")

        #expect(zsh.dumpPrompt()?.shown == "FULL:main › ")
        #expect(!server.received.contains { $0.hasPrefix("line\t") })
    }

    @Test func inputDisabledInstallsNoWidgets() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path, extra: ["SMALTI_INPUT_FEATURES": "0"])
        defer { zsh.close() }

        zsh.type("\r", settle: 0.4)

        #expect(zsh.dumpPrompt()?.tab.contains("smalti-complete") == false)
    }

    @Test func fullPromptKeepsTheOSC133Marks() throws {
        let server = try FakeInputServer(reply: Self.answering(branch: "main"))
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.5)
        let raw = zsh.dumpPrompt()?.raw ?? ""

        #expect(raw.contains("FULL:"))
        #expect(raw.contains("]133;A"))
        #expect(raw.contains("]133;B"))
    }
}

/// Block 3 review (I4, M1–M4): the user's psvar, Ghostty's marks, the first prompt's exit and styles sent during vared.
@Suite("zsh prompt from Smalti · review", .serialized)
struct PromptScriptReviewTests {
    private typealias Base = PromptScriptIntegrationTests

    private func styled() throws -> FakeInputServer {
        try FakeInputServer { fields in fields.first == "hello" ? [Base.style()] : [] }
    }

    @Test func userPrecmdClearingPsvarKeepsTheSymbol() throws {
        let server = try styled()
        let zsh = try ZshHarness(socket: server.path, zshrc: "precmd() { psvar=(rama) }")
        defer { zsh.close() }

        zsh.type("cd /usr/local/bin\r", settle: 0.5)

        #expect(zsh.dumpPrompt()?.shown == "IMM:local/bin › ")
    }

    @Test func shellSourceGivesTheUserPsvarBack() throws {
        let server = try styled()
        let zsh = try ZshHarness(socket: server.path, zshrc: "psvar=(mio)\nPS1='u%1v '")
        defer { zsh.close() }
        zsh.type("\r", settle: 0.4)

        server.push(Base.style(immediate: ""))
        zsh.type("\r", settle: 0.4)

        #expect(zsh.dumpPrompt()?.shown == "umio ")
    }

    @Test func restoredUserPromptHasOneSetOfMarks() throws {
        let server = try styled()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("\r", settle: 0.4)

        server.push(Base.style(immediate: ""))
        zsh.type("\r", settle: 0.4)
        zsh.type("\r", settle: 0.4)
        let raw = zsh.dumpPrompt()?.raw ?? ""

        #expect(raw.components(separatedBy: "133;A").count == 2, "\(raw)")
    }

    @Test func twoLineImmediatePromptMarksItsSecondLine() throws {
        let server = try FakeInputServer { fields in
            switch fields.first {
            case "hello": ["promptstyle\tIMM:%2v\\n%1v \t#5f6672\t1=›"]
            case "context": [Base.prompt(seq: fields[1], branch: "main")]
            default: []
            }
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("\r", settle: 0.4)
        server.stopAnswering()
        zsh.type("\r", settle: 0.4)

        #expect(zsh.dumpPrompt()?.raw.contains("133;P;k=s") == true)
    }

    @Test func firstContextCarriesTheLastStartupStatus() throws {
        let server = try styled()
        let zsh = try ZshHarness(socket: server.path, zshrc: "false")
        defer { zsh.close() }

        _ = server.waitFor { $0.contains { $0.hasPrefix("context\t") } }
        let first = server.received.first { $0.hasPrefix("context\t") }?.components(separatedBy: "\t")

        #expect(first?[3] == "1")
    }

    @Test func styleSentDuringVaredStillApplies() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("vared -c answer\r", settle: 0.4)
        server.push(Base.style())
        zsh.type("x\r", settle: 0.4)
        zsh.type("\r", settle: 0.4)

        #expect(zsh.dumpPrompt()?.shown.hasPrefix("IMM:") == true)
    }
}
