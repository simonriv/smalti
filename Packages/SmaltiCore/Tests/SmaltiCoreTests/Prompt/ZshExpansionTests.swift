import Foundation
import SmaltiCore
import Testing

/// Block 2 review (C1): the renderer's strings expanded by a real zsh (`print -P` with `psvar`), so a string zsh
/// would cut or misread fails here instead of being pinned as text.
@Suite("Prompt strings in zsh", .enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/zsh")))
struct ZshExpansionTests {
    /// What zsh prints for `prompt` with `variables` assigned and `$?` = `exit`, escape sequences removed.
    private func expand(_ prompt: String, _ variables: [String: String], exit: Int = 0) throws -> String {
        // psvar slots by number (spec F5: values are shown with `%Nv`, never expanded); no prompt_subst needed.
        let assignments = variables.compactMap { key, value in Int(key).map { "psvar[\($0)]=\(quoted(value))" } }
        let script = (assignments + ["(exit \(exit))", "print -rnP -- \(quoted(prompt))"])
            .joined(separator: "\n")
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-f", "-c", script]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func immediate(_ change: (inout PromptConfig) -> Void = { _ in }) -> RenderedPrompt {
        var config = PromptConfig.standard
        change(&config)
        var appearance = AppearanceSettings.obsidian
        appearance.protectLegibility = false
        return ZshPromptRenderer.render(
            config, context: PromptContext(directory: "/tmp", home: "/Users/simon"),
            theme: ThemeCatalog.apply(appearance))
    }

    @Test func immediateWithoutDurationShowsDirectoryAndSymbol() throws {
        let prompt = immediate()

        let shown = try expand(prompt.immediate, ["2": "solen", "3": "", "1": "›"])

        #expect(shown == "\u{E900} solen\n› ")
    }

    @Test func immediateWithDurationShowsIt() throws {
        let prompt = immediate()

        let shown = try expand(
            prompt.immediate, ["2": "solen", "3": "4.2s", "1": "›"])

        #expect(shown == "\u{E900} solen   4.2s\n› ")
    }

    @Test func failedExitShowsExitCode() throws {
        let shown = try expand(
            immediate().immediate, ["2": "x", "3": "", "1": "›"], exit: 3)

        #expect(shown == "\u{E900} x\n› exit 3 ")
    }

    @Test func pillsImmediateWithoutDurationLeavesNothing() throws {
        let prompt = immediate { $0 = $0.applying(.pills) }

        let shown = try expand(prompt.immediate, ["2": "solen", "3": "", "1": "›"])

        #expect(shown == " \u{E900} solen  › ")
    }

    @Test func fullPromptValuesStayLiteral() throws {
        var context = PromptContext(directory: "/tmp", home: "/Users/simon")
        context.branch = "$(touch /tmp/smalti-pwned)`id`%F{red}"
        var config = PromptConfig.standard
        config.modules = [.gitBranch]
        let prompt = ZshPromptRenderer.render(config, context: context, theme: ThemeCatalog.apply(.obsidian))

        let shown = try expand(prompt.full, prompt.values)

        #expect(shown.hasPrefix("\u{E901} $(touch /tmp/smalti-pwned)`id`%F{red}"))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/smalti-pwned"))
    }
}
