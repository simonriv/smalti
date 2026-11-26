import SmaltiCore
import Testing

/// Spec F5, "Estudio de prompt": the model, its `theme.toml` names and the templates as style + layout.
@Suite("PromptConfig")
struct PromptConfigTests {
    @Test func standardPromptMatchesBoard() {
        let standard = PromptConfig.standard

        #expect(standard.source == .smalti)
        #expect(standard.style == .clean)
        #expect(standard.layout == .twoLines)
        #expect(standard.modules == [.directory, .gitBranch, .gitStatus, .runtime, .duration, .agents])
        #expect(standard.icons == .thin)
        #expect(standard.symbol == .chevron)
    }

    @Test func configNamesMatchSpec() {
        #expect(
            PromptModuleID.allCases.map(\.rawValue) == [
                "directory", "git-branch", "git-status", "runtime", "duration", "agents", "time", "cloud",
            ])
        #expect(PromptStyleID.allCases.map(\.rawValue) == ["clean", "pills", "symbol-only"])
        #expect(PromptLayout.allCases.map(\.rawValue) == ["two-lines", "one-line"])
        #expect(PromptIcons.allCases.map(\.rawValue) == ["thin", "nerd", "none"])
        #expect(PromptSymbol.allCases.map(\.rawValue) == ["›", "❯", "λ", "$"])
        #expect(PromptSource.allCases.map(\.rawValue) == ["smalti", "shell"])
    }

    @Test func moduleTitlesMatchBoard() {
        #expect(
            PromptModuleID.allCases.map { $0.title(.spanish) } == [
                "Directorio", "Rama git", "Cambios git", "Runtime", "Duración", "Agentes que esperan", "Hora",
                "Contexto de Kubernetes / AWS",
            ])
        #expect(PromptModuleID.directory.detail(.spanish) == "últimos 2 niveles")
        #expect(PromptModuleID.gitStatus.detail(.spanish) == "●2 +1")
        #expect(PromptModuleID.runtime.detail(.spanish) == "Node, Bun, Python, Go")
        #expect(PromptModuleID.duration.detail(.spanish) == "si pasa de 2 s")
        #expect(PromptModuleID.time.detail(.spanish) == nil)
    }

    @Test(arguments: [
        (PromptTemplate.cleanLine, PromptStyleID.clean, PromptLayout.twoLines),
        (.singleLine, .clean, .oneLine), (.pills, .pills, .oneLine), (.symbolOnly, .symbolOnly, .twoLines),
    ])
    func templatesMapToStyleAndLayout(_ template: PromptTemplate, _ style: PromptStyleID, _ layout: PromptLayout) {
        let config = PromptConfig.standard.applying(template)

        #expect(config.style == style)
        #expect(config.layout == layout)
        #expect(config.template == template)
    }

    @Test func templateNamesMatchBoard() {
        #expect(
            PromptTemplate.allCases.map { $0.title(.spanish) } == [
                "Línea limpia", "Una sola línea", "Píldoras", "Solo símbolo",
            ])
    }

    @Test func applyingTemplateKeepsModulesIconsAndSymbol() {
        var config = PromptConfig.standard
        config.modules = [.time]
        config.icons = .none
        config.symbol = .lambda

        let applied = config.applying(.pills)

        #expect(applied.modules == [.time])
        #expect(applied.icons == PromptIcons.none)
        #expect(applied.symbol == .lambda)
    }

    @Test func changingLayoutMovesTemplateMark() {
        var config = PromptConfig.standard.applying(.cleanLine)

        config.layout = .oneLine

        #expect(config.template == .singleLine)
    }

    @Test func symbolOnlyIgnoresLayout() {
        var config = PromptConfig.standard.applying(.symbolOnly)

        config.layout = .oneLine

        #expect(config.template == .symbolOnly)
    }

    @Test func pillsInTwoLinesMatchesNoTemplate() {
        var config = PromptConfig.standard.applying(.pills)

        config.layout = .twoLines

        #expect(config.template == nil)
    }

    @Test func standardConfigCarriesStandardPrompt() {
        #expect(SmaltiConfig.defaults.prompt == .standard)
    }

    @Test func windowButtonsDefaultToHidden() {
        #expect(WindowSettings.standard.buttons == .hidden)
        #expect(WindowButtons.allCases.map(\.rawValue) == ["hidden", "hover", "visible"])
    }
}
