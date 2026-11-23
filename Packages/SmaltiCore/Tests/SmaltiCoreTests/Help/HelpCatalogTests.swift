import SmaltiCore
import Testing

@Suite("HelpCatalog")
struct HelpCatalogTests {
    private let sections = HelpCatalog.sections(keymap: .standard)

    private func entry(_ title: String) -> HelpEntry? {
        sections.flatMap(\.entries).first { $0.title == title }
    }

    /// C1: every command the app ships is in the help.
    @Test func everyStandardCommandIsInHelp() {
        let covered = Set(sections.flatMap(\.entries).flatMap(\.covers))

        let missing = CommandID.allStandard.filter { !covered.contains($0) }

        #expect(missing.isEmpty, "missing: \(missing.map(\.rawValue))")
    }

    @Test func sectionsInSpecOrder() {
        #expect(
            sections.map(\.title) == [
                "Ventanas y workspaces", "Paneles", "Terminal", "Buscar", "Tiling", "Agentes y observatorio",
                "En el prompt", "Ratón", "Configuración y ayuda",
            ])
    }

    @Test func entryShowsTheKeymapChord() {
        #expect(entry("Nueva ventana")?.keys == "⌘N")
        #expect(entry("Nueva ventana")?.command == .windowNew)
    }

    @Test func helpUnboundCommandSaysInPalette() {
        #expect(entry("Renombrar workspace…")?.keys == "en ⌘K")
    }

    @Test func numberedFamiliesShowTheirRange() {
        #expect(entry("Ir al panel 1–9")?.keys == "⌘1…⌘9")
        #expect(entry("Ir al workspace 1–9")?.keys == "⌃1…⌃9")
        #expect(entry("Ir al panel 1–9")?.command == nil)
    }

    @Test func directionalFamiliesShareModifiers() {
        #expect(entry("Enfocar panel hacia…")?.keys == "⌥⌘←→↑↓")
    }

    @Test func familyWithAReboundMemberListsEachChord() throws {
        let keymap = try Keymap.standard.overriding([try KeyChord.parse("cmd+opt+left"): nil])

        let keys = HelpCatalog.sections(keymap: keymap).flatMap(\.entries).first { $0.title == "Enfocar panel hacia…" }?
            .keys

        #expect(keys == "⌥⌘→ ⌥⌘↑ ⌥⌘↓")
    }

    @Test func helpFixedSectionsPresent() {
        #expect(entry("Completar")?.keys == "Tab")
        #expect(entry("Aceptar sugerencia")?.keys == "→")
        #expect(entry("Buscar en el historial")?.keys == "⌃R")
        #expect(entry("Abrir un enlace")?.keys == "⌘clic")
        #expect(entry("Pegar la ruta de un archivo")?.keys == "arrastrar")
        #expect(entry("Menú del terminal")?.keys == "clic derecho")
        #expect(entry("Abrir un enlace")?.command == nil)
    }

    @Test func helpFilterKeepsMatchingEntriesAndDropsEmptySections() {
        let filtered = HelpCatalog.filtered(sections, query: "ventana")

        #expect(filtered.map(\.title) == ["Ventanas y workspaces"])
        #expect(filtered[0].entries.allSatisfy { $0.title.lowercased().contains("ventana") })
    }

    @Test func emptyQueryKeepsEverything() {
        #expect(HelpCatalog.filtered(sections, query: "  ") == sections)
    }

    @Test func noMatchesGivesNoSections() {
        #expect(HelpCatalog.filtered(sections, query: "zzzz").isEmpty)
    }
}
