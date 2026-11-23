import Foundation
import Testing

/// F4 T12 (spec C7, amendment 1): ⌃R asks Smalti for its history palette and Tab uses Smalti's specs, falling back
/// to the widget the user's `.zshrc` left on Tab. Here that widget is a marker, so the tests can see it ran.
@Suite("zsh bindings", .serialized)
struct ZshBindingsTests {
    private static let userTab = """
        _test_tab() { BUFFER+="<user-tab>"; CURSOR=${#BUFFER} }
        zle -N _test_tab
        bindkey '^I' _test_tab
        """

    private static func specs(_ fields: [String]) -> [String] {
        fields.first == "hello" ? ["specs\tgit npm"] : []
    }

    @Test func ctrlRSendsHistory() throws {
        let server = try FakeInputServer(reply: Self.specs)
        let zsh = try ZshHarness(socket: server.path, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("swi\u{12}")

        #expect(server.waitFor { lines in lines.contains { $0.hasPrefix("history\t") && $0.hasSuffix("\tswi") } })
    }

    @Test func tabWithoutSpecRunsUserWidget() throws {
        let server = try FakeInputServer(reply: Self.specs)
        let zsh = try ZshHarness(socket: server.path, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("ls \t")

        #expect(zsh.dump()?.buffer == "ls <user-tab>")
        #expect(!server.received.contains { $0.hasPrefix("complete") })
    }

    @Test func tabOnTheCommandNameRunsUserWidget() throws {
        let server = try FakeInputServer(reply: Self.specs)
        let zsh = try ZshHarness(socket: server.path, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("gi\t")

        #expect(zsh.dump()?.buffer == "gi<user-tab>")
    }

    @Test func tabBeforeSpecsArriveRunsUserWidget() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("git ch\t")

        #expect(zsh.dump()?.buffer == "git ch<user-tab>")
    }

    @Test func tabWithSpecSendsComplete() throws {
        let server = try FakeInputServer(reply: Self.specs)
        let zsh = try ZshHarness(socket: server.path, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("ls && git ch\t")

        #expect(
            server.waitFor { lines in
                lines.contains { $0.hasPrefix("complete\t") && $0.hasSuffix("\t12\tls && git ch") }
            })
        #expect(zsh.dump()?.buffer == "ls && git ch")
    }

    @Test func fallbackReplyRunsUserWidget() throws {
        let server = try FakeInputServer { fields in
            switch fields.first {
            case "hello": return ["specs\tgit"]
            case "complete": return ["fallback\t\(fields[1])"]
            default: return []
            }
        }
        let zsh = try ZshHarness(socket: server.path, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("git zz\t", settle: 0.4)

        #expect(zsh.dump()?.buffer == "git zz<user-tab>")
    }

    /// ⌘↩ in the palette: Smalti sends `edit` and then types Return. Enter applies any answer already waiting, so
    /// the edited line runs even when Return is read before the socket.
    @Test func enterRunsTheLineSmaltiJustEdited() throws {
        let server = try FakeInputServer { fields in
            fields.first == "history" ? ["edit\t\(fields[1])\t10\tprint -r -- EDITED"] : []
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("pri\u{12}", settle: 0)
        _ = server.waitFor { $0.contains { $0.hasPrefix("history") } }
        zsh.type("\r", settle: 0.8)

        // The command's own output follows the OSC 133;C mark, unlike the echo of the line.
        #expect(zsh.printed.contains("133;C\u{07}EDITED"))
        #expect(
            server.waitFor { lines in lines.contains { $0.hasPrefix("exec\t") && $0.hasSuffix("print -r -- EDITED") } })
    }

    @Test func enterStillRunsTheUsersWidget() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(
            socket: server.path,
            zshrc: "_test_enter() { BUFFER+=' # mine'; zle .accept-line }\nzle -N _test_enter\nbindkey '^M' _test_enter"
        )
        defer { zsh.close() }

        zsh.type("print -r -- ENTER\r", settle: 0.6)

        #expect(server.waitFor { $0.contains { $0.hasSuffix("print -r -- ENTER # mine") } })
    }

    @Test func withoutSocketBindingsStayAsZshrcLeftThem() throws {
        let zsh = try ZshHarness(socket: nil, zshrc: Self.userTab)
        defer { zsh.close() }

        zsh.type("git ch\t")

        #expect(zsh.dump()?.buffer == "git ch<user-tab>")
    }

    // MARK: Block 3 review

    /// I3: vi-mode users keep their own Tab.
    @Test func viModeKeepsTheUsersTab() throws {
        let server = try FakeInputServer(reply: Self.specs)
        let zsh = try ZshHarness(
            socket: server.path,
            zshrc:
                "bindkey -v\n_test_vtab() { BUFFER+='<vi-tab>'; CURSOR=${#BUFFER} }\nzle -N _test_vtab\nbindkey -M viins '^I' _test_vtab"
        )
        defer { zsh.close() }

        zsh.type("ls \t")

        #expect(zsh.dump()?.buffer == "ls <vi-tab>")
    }

    /// I4: with the channel off, ⌃R does what it did before.
    @Test func ctrlRFallsBackWhenTheChannelIsOff() throws {
        let server = try FakeInputServer(mode: .closesAfter(2))
        let zsh = try ZshHarness(
            socket: server.path, zshrc: "_test_r() { BUFFER+='<user-r>' }\nzle -N _test_r\nbindkey '^R' _test_r")
        defer { zsh.close() }
        zsh.type("abc", settle: 0.5)

        zsh.type("\u{15}\u{12}")

        #expect(zsh.dump()?.buffer == "<user-r>")
    }

    /// I4: vi's command mode keeps ⌃R as redo.
    @Test func viCommandModeKeepsItsCtrlR() throws {
        let server = try FakeInputServer()
        let zsh = try ZshHarness(socket: server.path, zshrc: "bindkey -v")
        defer { zsh.close() }

        zsh.type("print -r -- $(bindkey -M vicmd '^R')\r", settle: 0.6)

        #expect(zsh.printed.contains("redo"))
    }

    /// Block 4 review m1: Return right after a dropped ⌘↩ edit never runs the old line.
    @Test func returnAfterAStaleRunningEditIsRefused() throws {
        let server = try FakeInputServer { fields in
            fields.first == "history" ? ["editrun\t\((Int(fields[1]) ?? 1) - 1)\t2\tls"] : []
        }
        let zsh = try ZshHarness(socket: server.path)
        defer { zsh.close() }

        zsh.type("print -r -- OLD\u{12}", settle: 0.5)
        zsh.type("\r", settle: 0.6)

        #expect(!server.received.contains { $0.hasPrefix("exec\t") })
        zsh.type("\r", settle: 0.6)
        #expect(server.waitFor { $0.contains { $0.hasPrefix("exec\t") && $0.hasSuffix("print -r -- OLD") } })
    }
}
