import XCTest

/// config.toml end to end (spec F1, R2): errors in the status bar, "Recargar configuración" and the shell from the
/// file. Every launch reads its own fixture in a temporary directory, never the user's file, and runs `zsh -f`.
final class ConfigTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let isolatedShellSection = """
        [shell]
        command = "\(XCUIApplication.isolatedShell)"
        """

    func testInvalidValueAtStartupShowsFileLineAndKey() {
        launch(.isolatedSmalti(config: "[appearance]\nglass_opacity = 0.5\nblur = 99\n"))

        expect(app.element("smalti.statusBar"), value: "config.toml:3 · blur: se esperaba un número entre 0 y 48")
    }

    /// I1: `glass_opacity` and `blur` change the glass without a restart.
    func testReloadRepaintsTheGlass() {
        launch(.isolatedSmalti(config: "[appearance]\nglass_opacity = 0.3\nblur = 28\n"))
        let glass = app.element("smalti.glass")
        expect(glass, value: "vidrio 0.30 · desenfoque 28")
        app.writeConfig("[appearance]\nglass_opacity = 0.95\nblur = 10\n")

        reloadConfigFromPalette()

        expect(glass, value: "vidrio 0.95 · desenfoque 10")
    }

    func testReloadAppliesNewKeyBindings() {
        launch(.isolatedSmalti())
        app.writeConfig("[keys]\n\"cmd+j\" = \"pane.new\"\n")
        reloadConfigFromPalette()

        app.typeKey("j", modifierFlags: .command)

        waitForPaneCount(2)
    }

    /// Without `-SmaltiShellCommand` the shell comes from `[shell] command`; `zsh -f` leaves the `rcs` option off.
    func testShellComesFromTheConfigFile() {
        let clientsBefore = TmuxClients.count()
        launch(.isolatedSmalti(shell: nil, config: Self.isolatedShellSection))

        app.run("[[ -o rcs ]] && r=on || r=off; <<<$SMALTI-$r>\"$SMALTI_UITEST_OUT\"")

        waitForOutput("1-off\n")
        XCTAssertEqual(app.elements("smalti.paneHeader").firstMatch.label, "zsh")
        if let clientsBefore { XCTAssertEqual(TmuxClients.count(), clientsBefore) }
    }
}
