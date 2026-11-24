import Foundation
import SmaltiCore
import Testing

/// F5.6 T8 (spec C4, C5): zsh paints Smalti's `highlight` spans with the `highlightstyle` colors, decides whether a
/// command exists, keeps the unchanged prefix while the answer is on its way and leaves the ghost alone.
@Suite("zsh input highlighting", .serialized)
struct ZshHighlightTests {
    private static let style = "highlightstyle\t#7aa2f7\t#f7768e\t#7dcfff\t#bb9af7\t#9ece6a\t#8b919c"
    private static let blue = "fg=#7aa2f7 memo=smaltihl"
    private static let red = "fg=#f7768e memo=smaltihl"

    /// The style at `hello` and, for every `line`, the spans `LineHighlighter` gives (no specs), with its seq.
    private static func highlighting(_ fields: [String]) -> [String] {
        switch fields.first {
        case "hello": return [style]
        case "line" where fields.count >= 5:
            let buffer = fields[4].replacingOccurrences(of: "\\t", with: "\t")
            let plan = LineHighlighter.plan(for: buffer) { _ in nil }
            return [InputProtocol.encode(.highlight(seq: Int(fields[1]) ?? 0, plan.spans))]
        default: return []
        }
    }

    /// The style only: spans arrive by `push`.
    private static func styleOnly(_ fields: [String]) -> [String] {
        fields.first == "hello" ? [style] : []
    }

    private func entries(_ zsh: ZshHarness) -> String {
        zsh.dump()?.highlight ?? ""
    }

    private func smaltiEntries(_ zsh: ZshHarness) -> [String] {
        let all = entries(zsh)
        let pattern = /\d+ \d+ [^ ]+ memo=smaltihl/
        return all.matches(of: pattern).map { String($0.output) }
    }

    @Test func paintsSpansWithStyleColors() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ls -la")

        #expect(smaltiEntries(zsh) == ["0 2 \(Self.blue)", "3 6 fg=#bb9af7 memo=smaltihl"])
    }

    @Test func ignoresHighlightWithOldSeq() throws {
        let server = try FakeInputServer(mode: .staleSeq, reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ls -la")

        #expect(!entries(zsh).contains("memo=smaltihl"))
    }

    @Test func lateHighlightForOldLineIsDropped() throws {
        let server = try FakeInputServer(reply: Self.styleOnly)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("ls")
        let seqs = server.received.filter { $0.hasPrefix("line\t") }.compactMap { Int($0.split(separator: "\t")[1]) }
        let latest = try #require(seqs.max())

        server.push("highlight\t\(latest - 1)\t0,1,c")
        zsh.type("")
        #expect(smaltiEntries(zsh).isEmpty)
        server.push("highlight\t\(latest)\t0,2,c")
        zsh.type("")

        #expect(smaltiEntries(zsh) == ["0 2 \(Self.blue)"])
    }

    @Test func secondHighlightReplacesFirst() throws {
        let server = try FakeInputServer(reply: Self.styleOnly)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("ls")
        let latest = try #require(
            server.received.filter { $0.hasPrefix("line\t") }.compactMap { Int($0.split(separator: "\t")[1]) }.max())

        server.push("highlight\t\(latest)\t0,2,c")
        server.push("highlight\t\(latest)\t0,1,o")
        zsh.type("")

        #expect(smaltiEntries(zsh) == ["0 1 fg=#bb9af7 memo=smaltihl"])
    }

    @Test(arguments: ["al", "fn", "cd", "if", "./tool", "ls"])
    func knownCommandIsBlue(_ word: String) throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path, zshrc: "alias al=ls\nfn() { : }\ncd \"$HOME\"")
        defer { zsh.close() }
        let tool = zsh.work.appending(path: "tool")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))

        zsh.type(word + " ")

        #expect(smaltiEntries(zsh).first == "0 \(word.count) \(Self.blue)")
    }

    @Test func unknownCommandRedOnlyOutsideWord() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("gti")
        #expect(smaltiEntries(zsh).isEmpty)
        zsh.type(" ")

        #expect(smaltiEntries(zsh) == ["0 3 \(Self.red)"])
    }

    @Test func cursorMoveRecolorsWithoutServer() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("gti st")
        #expect(smaltiEntries(zsh) == ["0 3 \(Self.red)"])
        server.stopAnswering()

        zsh.type("\u{1b}[D\u{1b}[D\u{1b}[D\u{1b}[D")

        #expect(smaltiEntries(zsh).isEmpty)
    }

    @Test func pathSpanIsUnderline() throws {
        let server = try FakeInputServer(reply: Self.styleOnly)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("cat ab")
        let latest = try #require(
            server.received.filter { $0.hasPrefix("line\t") }.compactMap { Int($0.split(separator: "\t")[1]) }.max())

        server.push("highlight\t\(latest)\t4,6,q 4,6,p")
        zsh.type("")

        #expect(smaltiEntries(zsh) == ["4 6 fg=#9ece6a memo=smaltihl", "4 6 underline memo=smaltihl"])
    }

    @Test func editingMiddleDropsSpansAfterChange() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("ls -la")
        server.stopAnswering()

        zsh.type("\u{01}x")

        #expect(smaltiEntries(zsh).isEmpty)
    }

    @Test func appendingKeepsPrefixSpans() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("ls -l")
        server.stopAnswering()

        zsh.type("a")

        #expect(smaltiEntries(zsh) == ["0 2 \(Self.blue)"])
    }

    @Test func ghostUntouchedByHighlight() throws {
        let server = try FakeInputServer { fields in
            var answers = Self.highlighting(fields)
            if fields.first == "line", fields.last == "git s" { answers.append("suggest\t\(fields[1])\ttatus") }
            return answers
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("git s")

        let state = try #require(zsh.dump())
        #expect(state.ghost == "tatus")
        #expect(state.highlight.contains("fg=#5f6672 memo=smalti"))
        #expect(state.highlight.contains("0 3 \(Self.red)") || state.highlight.contains("0 3 \(Self.blue)"))
    }

    @Test func styleOffClearsSpans() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        zsh.type("ls -la")
        #expect(!smaltiEntries(zsh).isEmpty)

        server.push("highlightstyle\toff")
        zsh.type("")

        #expect(smaltiEntries(zsh).isEmpty)
    }

    @Test func hostileCommandWordIsNotEvaluated() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }
        let dollar = zsh.work.appending(path: "pwned").path(percentEncoded: false)
        let backtick = zsh.work.appending(path: "pwned2").path(percentEncoded: false)

        zsh.type("$(touch \(dollar)) ")
        zsh.type("\u{15}`touch \(backtick)` ")
        zsh.type("\u{15}~root/x ")

        #expect(!FileManager.default.fileExists(atPath: dollar))
        #expect(!FileManager.default.fileExists(atPath: backtick))
        #expect(smaltiEntries(zsh).first?.hasSuffix(Self.red) == true)
    }

    @Test func multibyteLineHighlightsRightWord() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("echo 👍🏽 \"x\"")

        #expect(smaltiEntries(zsh) == ["0 4 \(Self.blue)", "8 11 fg=#9ece6a memo=smaltihl"])
    }

    @Test func regionSelectionStaysVisible() throws {
        let server = try FakeInputServer(reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path, zshrc: "bindkey '^X^M' set-mark-command")
        defer { zsh.close() }
        zsh.type("ls -la")
        let before = zsh.printed.count

        zsh.type("\u{18}\u{0d}\u{01}")

        let after = String(zsh.printed.dropFirst(before))
        #expect(after.contains("\u{1b}[7m"))
    }

    @Test func noSmaltiMeansPlainShell() throws {
        let server = try FakeInputServer(mode: .closesAfter(3), reply: Self.highlighting)
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("ls -la")
        zsh.type(" x")

        let state = try #require(zsh.dump())
        #expect(state.buffer == "ls -la x")
        #expect(!state.highlight.contains("memo=smaltihl"))
    }
}
