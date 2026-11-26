import SmaltiCore
import Testing

/// Spec F5, "Exportar como starship.toml": what each module and the symbol become in Starship.
@Suite("StarshipPreset")
struct StarshipPresetTests {
    private var theme: AppliedTheme {
        var appearance = AppearanceSettings.obsidian
        appearance.protectLegibility = false
        return ThemeCatalog.apply(appearance)
    }

    private func preset(_ change: (inout PromptConfig) -> Void = { _ in }) -> StarshipPreset {
        var config = PromptConfig.standard
        change(&config)
        return StarshipPreset.make(from: config, theme: theme, copy: .spanish)
    }

    @Test func formatFollowsModulesAndLayout() {
        #expect(
            preset().format
                == "$directory$git_branch$git_status$nodejs$bun$python$golang$cmd_duration$line_break$character")
    }

    @Test func oneLineHasNoLineBreak() {
        #expect(!preset { $0.layout = .oneLine }.format.contains("$line_break"))
    }

    @Test func symbolOnlyExportsOnlyTheCharacter() {
        #expect(preset { $0.style = .symbolOnly }.format == "$character")
    }

    @Test func directoryTruncatesToTwoLevelsAndRepo() {
        let directory = preset().table("directory")

        #expect(directory?.value("truncation_length") == .integer(2))
        #expect(directory?.value("truncate_to_repo") == .boolean(true))
        #expect(directory?.value("style") == .string("#7aa2f7"))
    }

    @Test func durationFromTwoSeconds() {
        #expect(preset().table("cmd_duration")?.value("min_time") == .integer(2000))
    }

    @Test func gitStatusShowsCounts() {
        let status = preset().table("git_status")

        #expect(status?.value("modified") == .string("●${count}"))
        #expect(status?.value("staged") == .string("+${count}"))
    }

    @Test func characterUsesSymbolAndColors() {
        let character = preset { $0.symbol = .lambda }.table("character")

        #expect(character?.value("success_symbol") == .string("[λ](#7aa2f7)"))
        #expect(character?.value("error_symbol") == .string("[λ](#f7768e)"))
    }

    @Test func starshipMapsEveryModule() {
        let all = preset { $0.modules = PromptModuleID.allCases }
        let tables = Set(all.tables.map(\.name))

        #expect(
            tables.isSuperset(of: [
                "directory", "git_branch", "git_status", "nodejs", "bun", "python", "golang", "cmd_duration", "time",
                "kubernetes", "aws", "character",
            ]))
        #expect(all.table("time")?.value("disabled") == .boolean(false))
        #expect(all.table("kubernetes")?.value("disabled") == .boolean(false))
    }

    @Test func starshipThinIconsExportWithoutSymbols() {
        let thin = preset()

        #expect(thin.table("git_branch")?.value("symbol") == .string(""))
        #expect(thin.table("nodejs")?.value("symbol") == .string(""))
    }

    @Test func nerdIconsExportNerdSymbols() {
        let nerd = preset { $0.icons = .nerd }

        #expect(nerd.table("git_branch")?.value("symbol") == .string("\u{E0A0} "))
    }

    @Test func starshipAgentsBecomesComment() {
        let comments = preset().comments

        #expect(comments.contains { $0.contains("Agentes que esperan") })
        #expect(preset().table("agents") == nil)
    }

    @Test func runtimeVersionShowsMajorAndMinor() {
        #expect(preset().table("nodejs")?.value("version_format") == .string("${major}.${minor}"))
    }
}

/// Block 2 review (I4, M7): text Starship would parse as format syntax is escaped, and the preset matches Smalti more.
@Suite("StarshipPreset · review")
struct StarshipPresetReviewTests {
    private func preset(_ change: (inout PromptConfig) -> Void = { _ in }) -> StarshipPreset {
        var config = PromptConfig.standard
        change(&config)
        var appearance = AppearanceSettings.obsidian
        appearance.protectLegibility = false
        return StarshipPreset.make(from: config, theme: ThemeCatalog.apply(appearance), copy: .spanish)
    }

    @Test func dollarSymbolIsEscaped() {
        let character = preset { $0.symbol = .dollar }.table("character")

        #expect(character?.value("success_symbol") == .string("[\\$](#7aa2f7)"))
    }

    @Test func noBlankLineBeforeThePrompt() {
        #expect(preset().settings.first { $0.key == "add_newline" }?.value == .boolean(false))
    }

    @Test func cloudOrderMatchesSmalti() {
        let names = preset { $0.modules = [.cloud] }.tables.map(\.name)

        #expect(names == ["aws", "kubernetes", "character"])
    }

    @Test func gitStatusColorsEachCount() {
        let format = preset().table("git_status")?.value("format")

        #expect(format == .string("([$modified](#e0af68))( [$staged](#9ece6a)) "))
    }
}

@Suite("StarshipPreset · notes")
struct StarshipPresetNotesTests {
    /// Block 2 review (M7): Starship cannot show the repository's name and two levels outside it at once.
    @Test func directoryDifferenceIsNoted() {
        let preset = StarshipPreset.make(from: .standard, theme: ThemeCatalog.apply(.obsidian), copy: .spanish)

        #expect(preset.comments.contains { $0.hasPrefix("Directorio:") })
    }

    @Test func noDirectoryNoNote() {
        var config = PromptConfig.standard
        config.modules = [.time]

        let preset = StarshipPreset.make(from: config, theme: ThemeCatalog.apply(.obsidian), copy: .spanish)

        #expect(!preset.comments.contains { $0.hasPrefix("Directorio:") })
    }
}
