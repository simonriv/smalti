import XCTest

/// F7: shared layouts. The save, open and folder panels and the confirmation are answered with Debug launch arguments
/// (`-SmaltiExportDirectory`, `-SmaltiImportFile`, `-SmaltiPickedFolder`, `-SmaltiConfirmImport`).
final class SharedLayoutTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    /// Where files are exported and fixtures written; outside the app's config folder, removed after each test.
    private var folder: URL!  // Created per test in setUp.

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "smalti-shared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: folder)
    }

    private func launchSharing(_ arguments: [String] = []) {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += ["-SmaltiExportDirectory", folder.path(percentEncoded: false)] + arguments
        launch(app)
    }

    /// A shared layout file with `panes` (each `{"directory": …}` object) rooted at `root`.
    private func writeShared(_ name: String, root: String, panes: [String], file: String = "equipo") throws -> URL {
        let tree =
            panes.count == 1
            ? #"{"leaf":{"index":0}}"#
            : (1..<panes.count).reduce(#"{"leaf":{"index":0}}"#) { tree, index in
                #"{"split":{"axis":"sideBySide","ratio":0.5,"first":\#(tree),"second":{"leaf":{"index":\#(index)}}}}"#
            }
        let json = """
            {"smaltiLayout":1,"name":"\(name)","root":"\(root)","layout":"dwindle","focused":0,"tree":\(tree),
            "panes":[\(panes.joined(separator: ","))]}
            """
        let url = folder.appending(path: "\(file).smalti-layout.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private func runFromPalette(_ query: String) {
        openPalette()
        app.typeText(query)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.element("smalti.palette").waitForNonExistence(timeout: 5))
    }

    private func expectStatus(_ text: String) {
        expect(app.element("smalti.statusBar"), value: text)
    }

    /// The palette's rows for `query`, read once the first row has drawn.
    private func paletteTitles(_ query: String) -> [String] {
        openPalette()
        app.typeText(query)
        _ = app.elements("smalti.paletteRow").firstMatch.waitForExistence(timeout: 5)
        let titles = app.elements("smalti.paletteRow").allElementsBoundByIndex.map(\.label)
        app.typeKey(.escape, modifierFlags: [])
        return titles
    }

    func testExportWritesPortableFile() throws {
        launchSharing()
        app.run("sleep 600")
        runFromPalette("compartir-ui")
        expectStatus("Layout “compartir-ui” guardado")
        app.typeKey("c", modifierFlags: .control)

        runFromPalette("exportar layout “compartir-ui”")

        expectStatus("Layout “compartir-ui” exportado")
        let text = try String(contentsOf: folder.appending(path: "compartir-ui.smalti-layout.json"), encoding: .utf8)
        XCTAssertTrue(text.contains(#""command" : ["#), text)
        XCTAssertTrue(text.contains(#""directory" : ".""#), text)
        XCTAssertTrue(text.contains(#""smaltiLayout" : 1"#), text)
        XCTAssertFalse(text.contains("sessionID"))
        XCTAssertFalse(text.contains("\"title\""))
        XCTAssertTrue(text.contains(#""sleep""#), text)
        XCTAssertFalse(text.contains(FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false) + "/"))
        XCTAssertFalse(text.contains("\"id\""))
        XCTAssertFalse(text.contains("scrollback"))
    }

    func testImportConfirmsThenAppearsInPaletteAndRestores() throws {
        let pane = #"{"directory":"."}"#
        let file = try writeShared("equipo", root: folder.path(percentEncoded: false), panes: [pane, pane, pane])
        launchSharing(["-SmaltiImportFile", file.path(percentEncoded: false), "-SmaltiConfirmImport", "yes"])

        runFromPalette("importar layout")

        expectStatus("Layout “equipo” importado")
        runFromPalette("restaurar layout “equipo”")
        waitForPaneCount(3)
    }

    func testImportCancelSavesNothing() throws {
        let file = try writeShared("equipo", root: "/tmp", panes: [#"{"directory":"."}"#])
        launchSharing(["-SmaltiImportFile", file.path(percentEncoded: false), "-SmaltiConfirmImport", "no"])

        runFromPalette("importar layout")

        let layouts = app.stateDirectory.appending(path: "layouts").path(percentEncoded: false)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: layouts)) ?? [], [])
        // Positive control: "layout" always lists "Importar layout…", so an empty list cannot pass by accident.
        let titles = paletteTitles("layout")
        XCTAssertTrue(titles.contains("Importar layout…"), "\(titles)")
        XCTAssertFalse(titles.contains("Restaurar layout “equipo”"), "\(titles)")
    }

    func testImportMissingRootAsksFolder() throws {
        let picked = FileManager.default.temporaryDirectory.appending(path: "smalti-picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: picked) }
        let file = try writeShared("lejos", root: "/nonexistent-\(UUID().uuidString)", panes: [#"{"directory":"."}"#])
        launchSharing([
            "-SmaltiImportFile", file.path(percentEncoded: false), "-SmaltiConfirmImport", "yes",
            "-SmaltiPickedFolder", picked.path(percentEncoded: false),
        ])

        runFromPalette("importar layout")
        expectStatus("Layout “lejos” importado")
        runFromPalette("restaurar layout “lejos”")
        waitForShells(count: 1)
        app.run(#"pwd -P > "$SMALTI_UITEST_OUT""#)

        // `pwd -P` gives the physical path (`/private/var/…`); compare both sides resolved.
        let expected = URL(filePath: picked.path(percentEncoded: false)).resolvingSymlinksInPath().path(
            percentEncoded: false)
        let output = outputFile!
        let opened = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let text = try? String(contentsOf: output, encoding: .utf8), !text.isEmpty else { return false }
                let shown = URL(filePath: text.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath()
                return shown.path(percentEncoded: false) == expected
            }, object: nil)
        wait(for: [opened], timeout: 10)
    }

    func testImportInvalidFileReportsReason() throws {
        let panes = Array(repeating: #"{"directory":"."}"#, count: 10)
        let file = try writeShared("grande", root: "/tmp", panes: panes)
        launchSharing(["-SmaltiImportFile", file.path(percentEncoded: false)])

        runFromPalette("importar layout")

        expectStatus("No se pudo importar el layout: tiene 10 paneles; el máximo es 9")
    }

    func testImportTakesFreeName() throws {
        let root = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        let file = try writeShared("equipo", root: root, panes: [#"{"directory":"."}"#])
        launchSharing(["-SmaltiImportFile", file.path(percentEncoded: false), "-SmaltiConfirmImport", "yes"])

        runFromPalette("importar layout")
        expectStatus("Layout “equipo” importado")
        runFromPalette("importar layout")

        expectStatus("Layout “equipo 2” importado")
    }
}
