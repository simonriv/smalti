import XCTest

/// F7.5 (C9, C11): ⌘K writes and removes Smalti's `permissions.deny` rules in a temporary project
/// (`-SmaltiProjectPermissionsRoot`), and offers updating an integration whose installed copy is older.
final class SecretRulesTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var project: URL { outputFile.appendingPathExtension("project") }
    private var settings: URL { project.appending(path: ".claude/settings.local.json") }

    private func row(_ title: String) -> XCUIElement {
        app.elements("smalti.paletteRow").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func launchWithProject(_ root: String? = nil) throws {
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let app = XCUIApplication.isolatedSmalti()
        // Review 2: every isolated launch already names a temporary project; this test names its own.
        let position = try XCTUnwrap(app.launchArguments.firstIndex(of: "-SmaltiProjectPermissionsRoot"))
        app.launchArguments[position + 1] = root ?? project.path(percentEncoded: false)
        launch(app)
    }

    /// Review 2 (I1): the home folder and the folders above it are never offered: their `.claude` is global.
    func testRootIsNeverOffered() throws {
        try launchWithProject("/")

        openPalette()
        app.typeText("secretos")

        XCTAssertFalse(row("Proteger secretos en “”").waitForExistence(timeout: 3))
        let offered = app.elements("smalti.paletteRow").matching(
            NSPredicate(format: "label BEGINSWITH 'Proteger secretos'"))
        XCTAssertEqual(offered.count, 0)
    }

    private func deniedRules() -> [String] {
        guard let data = try? Data(contentsOf: settings),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return (object["permissions"] as? [String: Any])?["deny"] as? [String] ?? []
    }

    private func waitForRules(count: Int) {
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in deniedRules().count == count }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [written], timeout: 5), .completed, "rules: \(deniedRules())")
    }

    /// No spaces: XCUITest sends them as ⌃Space on this layout.
    private func choose(_ query: String, title: String) {
        openPalette()
        app.typeText(query)
        XCTAssertTrue(row(title).waitForExistence(timeout: 5), "missing «\(title)»")
        app.typeKey(.return, modifierFlags: [])
    }

    func testProtectWritesRulesAndOffersUnprotect() throws {
        try launchWithProject()
        let name = project.lastPathComponent

        choose("protegersecretos", title: "Proteger secretos en “\(name)”")

        waitForRules(count: 34)
        XCTAssertTrue(deniedRules().contains("Read(**/.env)"))
        XCTAssertTrue(deniedRules().contains { $0.hasPrefix("Read(//") && $0.hasSuffix("/.ssh/**)") })
        openPalette()
        app.typeText("secretos")
        XCTAssertTrue(row("Quitar protección de secretos en “\(name)”").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Proteger secretos en “\(name)”").exists)
    }

    func testUnprotectRemovesThem() throws {
        try launchWithProject()
        let name = project.lastPathComponent
        choose("protegersecretos", title: "Proteger secretos en “\(name)”")
        waitForRules(count: 34)

        choose("quitarproteccion", title: "Quitar protección de secretos en “\(name)”")

        waitForRules(count: 0)
    }

    func testOutdatedIntegrationOffersUpdate() throws {
        let app = XCUIApplication.isolatedSmalti()
        app.useFakeClaude(installed: true)
        let manifest = app.stateDirectory.appending(path: "claude-plugin/plugins/smalti/.claude-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"name":"smalti","version":"0.1.0"}"#.utf8).write(to: manifest)
        launch(app)

        openPalette()
        app.typeText("integraci")

        XCTAssertTrue(row("Actualizar integración con Claude Code").waitForExistence(timeout: 10))
        XCTAssertFalse(row("Desinstalar integración con Claude Code").exists)
    }
}
