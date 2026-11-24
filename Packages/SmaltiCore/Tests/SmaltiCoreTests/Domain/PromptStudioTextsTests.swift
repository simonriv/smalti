import SmaltiCore
import Testing

/// `Prompt.dc.html`'s texts for the studio's choices, and the new ones of the spec.
@Suite("Prompt studio texts")
struct PromptStudioTextsTests {
    @Test func iconChoicesAreTheBoards() {
        #expect(PromptIcons.allCases.map(\.title) == ["Trazo fino", "Nerd Font", "Sin iconos"])
    }

    /// The board names the two-line layout; the one-line one takes the template's name.
    @Test func layoutTexts() {
        #expect(PromptLayout.twoLines.title == "Contexto arriba, input abajo")
        #expect(PromptLayout.oneLine.title == "Una sola línea")
    }

    @Test func onlySymbolOnlyCardHasANote() {
        #expect(PromptTemplate.allCases.compactMap(\.note) == ["· contexto en la cabecera"])
    }

    @Test func previewSituationsAreTheBoards() {
        #expect(
            PreviewSituation.allCases.map(\.title) == [
                "Carpeta normal", "Proyecto Node con git", "Después de un error, con agente activo",
            ])
    }

    @Test func specTexts() {
        #expect(PromptStudioTexts.shellPrompt == "Prompt del shell")
        #expect(PromptStudioTexts.noNerdFont == "No hay una Nerd Font instalada")
    }
}
