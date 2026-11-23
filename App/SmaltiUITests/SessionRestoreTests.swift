import XCTest

/// F2 part B: reopening brings the saved workspaces back.
final class SessionRestoreTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    func testAlwaysRestoreReopensWorkspaces() {
        let app = XCUIApplication.isolatedSmalti()
        SessionState.seed(
            [
                .init(
                    name: "solen", root: "/tmp", layout: "columns",
                    panes: [.init(directory: "/tmp"), .init(directory: "/usr")]),
                .init(name: "rizaria", root: "/usr", layout: "dwindle", panes: [.init(directory: "/usr")]),
            ], alwaysRestore: true, in: app)

        launch(app, shells: 2)

        let pills = app.elements("smalti.workspace")
        XCTAssertEqual(pills.allElementsBoundByIndex.map(\.label), ["solen", "rizaria"])
        expect(app.element("smalti.statusBar"), value: "solen · 2 paneles · columnas")
    }
}
