import XCTest

/// F6 (C11): ⌘K offers installing or uninstalling claudecode.nvim, never both, over an NvChad starter written in the
/// test's own `-SmaltiNvimConfigHome` (never `~/.config/nvim`).
final class IntegrationCatalogTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let install = "Instalar claudecode.nvim en Neovim"
    private static let uninstall = "Desinstalar claudecode.nvim"

    private func launch(nvChad: Bool) {
        let fresh = XCUIApplication.isolatedSmalti()
        if nvChad { writeStarter(at: URL(filePath: fresh.launchArgument("-SmaltiNvimConfigHome"))) }
        launch(fresh)
    }

    private func writeStarter(at config: URL) {
        do {
            try FileManager.default.createDirectory(
                at: config.appending(path: "lua/plugins"), withIntermediateDirectories: true)
            try #"require("lazy").setup({ { import = "plugins" } })"#.write(
                to: config.appending(path: "init.lua"), atomically: true, encoding: .utf8)
        } catch {
            XCTFail("could not write the NvChad starter: \(error)")
        }
    }

    private var pluginFile: URL {
        URL(filePath: app.launchArgument("-SmaltiNvimConfigHome")).appending(path: "lua/plugins/smalti-claudecode.lua")
    }

    private func row(_ title: String) -> XCUIElement {
        app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// No spaces: XCUITest sends them as ⌃Space on this layout.
    private func openPaletteOnClaudecode() {
        openPalette()
        app.typeText("claudecode")
    }

    func testPaletteOffersInstallClaudecodeOnNvChad() {
        launch(nvChad: true)

        openPaletteOnClaudecode()

        XCTAssertTrue(row(Self.install).waitForExistence(timeout: 10))
        XCTAssertFalse(row(Self.uninstall).exists)
    }

    func testInstallThenOffersUninstall() throws {
        launch(nvChad: true)
        openPaletteOnClaudecode()
        XCTAssertTrue(row(Self.install).waitForExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: [])

        openPaletteOnClaudecode()

        XCTAssertTrue(row(Self.uninstall).waitForExistence(timeout: 10))
        XCTAssertFalse(row(Self.install).exists)
        XCTAssertTrue(try String(contentsOf: pluginFile, encoding: .utf8).hasPrefix("-- Instalado por Smalti"))
    }

    func testNonNvChadOffersNeither() {
        launch(nvChad: false)

        openPaletteOnClaudecode()

        XCTAssertFalse(row(Self.install).waitForExistence(timeout: 3))
        XCTAssertFalse(row(Self.uninstall).exists)
    }
}
