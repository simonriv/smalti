import SmaltiCore
import Testing

/// `Prompt.dc.html`'s texts for the studio's choices, and the new ones of the spec.
@Suite("Prompt studio texts")
struct PromptStudioTextsTests {
    @Test func iconChoicesAreTheBoards() {
        #expect(PromptIcons.allCases.map { $0.title(.spanish) } == ["Trazo fino", "Nerd Font", "Sin iconos"])
    }

    /// The board names the two-line layout; the one-line one takes the template's name.
    @Test func layoutTexts() {
        #expect(PromptLayout.twoLines.title(.spanish) == "Contexto arriba, input abajo")
        #expect(PromptLayout.oneLine.title(.spanish) == "Una sola línea")
    }

    @Test func onlySymbolOnlyCardHasANote() {
        #expect(PromptTemplate.allCases.compactMap { $0.note(.spanish) } == ["· contexto en la cabecera"])
    }

    @Test func previewSituationsAreTheBoards() {
        #expect(
            PreviewSituation.allCases.map { $0.title(.spanish) } == [
                "Carpeta normal", "Proyecto Node con git", "Después de un error, con agente activo",
            ])
    }

    @Test func specTexts() {
        #expect(PromptCopy.spanish.shellPrompt == "Prompt del shell")
        #expect(PromptCopy.spanish.noNerdFont == "No hay una Nerd Font instalada")
    }
}
