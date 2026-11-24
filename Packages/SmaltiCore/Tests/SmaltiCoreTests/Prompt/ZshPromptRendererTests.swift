import SmaltiCore
import Testing

/// Spec F5, "Del dominio a zsh": the immediate and full prompt strings, with outside text only in `values`.
@Suite("ZshPromptRenderer")
struct ZshPromptRendererTests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    /// "Proyecto Node con git" of the board.
    private func nodeProject(_ change: (inout PromptContext) -> Void = { _ in }) -> PromptContext {
        var context = PromptContext(directory: "/Users/simon/dev/solen/apps/api", home: "/Users/simon")
        context.repoRoot = "/Users/simon/dev/solen"
        context.branch = "feat/reminders"
        context.changes = GitChanges(modified: 2, staged: 1)
        context.runtime = RuntimeVersion(kind: .node, version: "22.11")
        change(&context)
        return context
    }

    private func theme(protected: Bool = false, _ change: (inout AppearanceSettings) -> Void = { _ in })
        -> AppliedTheme
    {
        var appearance = AppearanceSettings.obsidian
        appearance.protectLegibility = protected
        change(&appearance)
        return ThemeCatalog.apply(appearance)
    }

    private func render(
        _ config: PromptConfig = .standard, _ context: PromptContext? = nil, theme applied: AppliedTheme? = nil
    ) -> RenderedPrompt {
        ZshPromptRenderer.render(config, context: context ?? nodeProject(), theme: applied ?? theme())
    }

    @Test func cleanTwoLinesMatchesGolden() {
        let rendered = render()

        #expect(
            rendered.full
                == "%F{#7aa2f7}\u{E900}%f %F{#7aa2f7}%4v%f   %F{#bb9af7}\u{E901}%f %F{#bb9af7}%5v%f "
                + "%F{#e0af68}%6v%f%F{#9ece6a}%7v%f   %F{#8b919c}\u{E902}%f %F{#8b919c}%8v%f"
                + "\n%F{#7aa2f7}%1v%f ")
        #expect(
            rendered.values == [
                "4": "solen/apps/api", "5": "feat/reminders", "6": "●2",
                "7": " +1", "8": "22.11", "1": "›",
            ])
        #expect(rendered.directoryLabel == "solen/apps/api")
    }

    @Test func oneLineMatchesGolden() {
        var config = PromptConfig.standard.applying(.singleLine)
        config.modules = [.directory]

        let rendered = render(config)

        #expect(rendered.full == "%F{#7aa2f7}\u{E900}%f %F{#7aa2f7}%4v%f %F{#7aa2f7}%1v%f ")
    }

    @Test func immediateHasOnlyLocalSegments() {
        let rendered = render()

        #expect(
            rendered.immediate
                == "%F{#7aa2f7}\u{E900}%f %F{#7aa2f7}%2v%f%(3V.   .)%F{#8b919c}%3v%f"
                + "\n%(?.%F{#7aa2f7}.%F{#f7768e})%1v%f%(?.. %F{#8b919c}exit %?%f) ")
    }

    @Test func immediateTimeUsesZshClock() {
        var config = PromptConfig.standard
        config.modules = [.time]

        #expect(render(config).immediate.hasPrefix("%F{#8b919c}\u{E906}%f %F{#8b919c}%D{%H:%M}%f\n"))
    }

    @Test func fullWithFailedExitPaintsSymbolRedAndAddsExit() {
        let rendered = render(.standard, nodeProject { $0.lastExit = 1 })

        #expect(rendered.full.hasSuffix("\n%F{#f7768e}%1v%f%F{#8b919c}%9v%f "))
        #expect(rendered.values["9"] == " exit 1")
    }

    @Test func branchWithSubstitutionStaysLiteral() {
        let rendered = render(.standard, nodeProject { $0.branch = "$(touch pwned)%F{red}" })

        #expect(rendered.values["5"] == "$(touch pwned)%F{red}")
        #expect(!rendered.full.contains("touch"))
        #expect(!rendered.full.contains("red"))
    }

    @Test func percentInDirectoryIsEscaped() {
        let rendered = render(
            .standard,
            nodeProject {
                $0.repoRoot = nil
                $0.directory = "/tmp/100%"
            })

        // Two levels in all: zsh's `%2~` shows the whole path, as for `/usr`. psvar shows `%` as is.
        #expect(rendered.values["4"] == "/tmp/100%")
    }

    @Test func newlineInNameIsReplaced() {
        let rendered = render(.standard, nodeProject { $0.branch = "a\nb\tc" })

        #expect(rendered.values["5"] == "a␤b c")
    }

    @Test func dollarSymbolNeverAppearsBareInThePrompt() {
        var config = PromptConfig.standard
        config.symbol = .dollar

        let rendered = render(config)
        let bare = rendered.full.split(separator: "$", omittingEmptySubsequences: false).dropFirst()
            .filter { !$0.hasPrefix("{") }

        #expect(bare.isEmpty)
        #expect(rendered.values["1"] == "$")
    }

    @Test func protectedColorsAreUsed() throws {
        let overrides = try ANSIOverrides([5: hex("#15161e")])
        let applied = theme(protected: true) { $0.ansiOverrides = [.obsidiana: overrides] }

        let full = render(.standard, nil, theme: applied).full

        #expect(full.contains("%F{\(applied.theme.terminal.palette[5].hexString)}%5v"))
        #expect(!full.contains("#15161e"))
    }

    @Test func noIconsLeaveNoGapsOrGlyphs() {
        var config = PromptConfig.standard
        config.icons = .none
        config.modules = [.directory]

        #expect(render(config).full == "%F{#7aa2f7}%4v%f\n%F{#7aa2f7}%1v%f ")
    }

    @Test func nerdIconsUseNerdGlyphs() {
        var config = PromptConfig.standard
        config.icons = .nerd

        #expect(render(config).full.hasPrefix("%F{#7aa2f7}\u{F07B}%f "))
    }

    @Test func pillsPaintTintedBackgrounds() {
        var config = PromptConfig.standard.applying(.pills)
        config.modules = [.directory]
        let applied = theme()
        let panel = applied.theme.panel.background
        let tint = PillsStyle.background(of: applied.theme.accent, over: panel).hexString

        let full = render(config, nil, theme: applied).full

        #expect(full.hasPrefix("%K{\(tint)} %k%K{\(tint)}%F{#7aa2f7}\u{E900}%f%k"))
    }

    @Test func symbolOnlyRendersOnlyTheSymbol() {
        #expect(render(PromptConfig.standard.applying(.symbolOnly)).full == "%F{#7aa2f7}%1v%f ")
    }

    @Test func messageStaysUnder2000Bytes() {
        let long = "/" + String(repeating: "a", count: 1500) + "/b"
        let rendered = render(
            .standard,
            nodeProject {
                $0.repoRoot = nil
                $0.directory = long
            })
        let size =
            rendered.full.utf8.count + rendered.immediate.utf8.count
            + rendered.values.map { $0.key.utf8.count + $0.value.utf8.count }.reduce(0, +)

        #expect(size < 2000)
        #expect(rendered.values["4"]?.hasPrefix("…") == true)
    }
}

/// Block 2 review (I3): the worst `prompt` answer still fits what Smalti may send in one write.
@Suite("ZshPromptRenderer · size")
struct ZshPromptSizeTests {
    @Test func worstCaseFitsAnAnswer() {
        var config = PromptConfig.standard.applying(.pills)
        config.modules = PromptModuleID.allCases
        let emoji = String(repeating: "🎉%", count: 200)
        var context = PromptContext(directory: "/" + emoji + "/" + emoji, home: "/Users/simon")
        context.branch = emoji
        context.changes = GitChanges(modified: 999_999, staged: 999_999)
        context.runtime = RuntimeVersion(kind: .node, version: emoji)
        context.duration = .seconds(99_999)
        context.agents = WaitingAgents(waiting: [emoji])
        context.awsProfile = emoji
        context.kubeContext = emoji
        context.lastExit = 255
        let rendered = ZshPromptRenderer.render(config, context: context, theme: ThemeCatalog.apply(.obsidian))

        let bytes = InputProtocol.encode(.prompt(seq: Int.max, rendered)).utf8.count + 1

        #expect(bytes <= InputProtocol.maximumAnswerBytes, "\(bytes) bytes")
    }

    @Test func trimmedValueKeepsWholeCharacters() {
        let literal = ZshEscaping.literal(String(repeating: "👩‍👩‍👧", count: 100))

        #expect(literal.utf8.count <= ZshEscaping.maximumBytes)
        #expect(literal.hasPrefix("…"))
        #expect(literal.dropFirst().allSatisfy { $0 == "👩‍👩‍👧" })
    }
}

@Suite("ZshPromptRenderer · whitespace")
struct ZshPromptWhitespaceTests {
    /// Block 2 review (M2): only plain spaces go raw; a name made of `\r` or U+2028 goes through the values.
    @Test func whitespaceNamesGoThroughValues() {
        var config = PromptConfig.standard
        config.modules = [.gitBranch]
        var context = PromptContext(directory: "/tmp", home: "/Users/simon")
        context.branch = "\r"

        let rendered = ZshPromptRenderer.render(config, context: context, theme: ThemeCatalog.apply(.obsidian))

        #expect(!rendered.full.contains("\r"))
        #expect(rendered.values["4"] == "␤")
    }
}
