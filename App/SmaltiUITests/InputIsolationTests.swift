import XCTest

/// F4 C15: the integrated shell of the input tests reads only its temporary ZDOTDIR and stays out of tmux.
final class InputIsolationTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    func testInputTestsUseAnIsolatedShell() {
        let app = XCUIApplication.isolatedSmaltiWithIntegration()
        launch(app)
        sleep(2)

        app.typeText("<<<\"$ZDOTDIR|$TMUX|${+_smalti_input_fd}\">\"$SMALTI_UITEST_OUT\"\n")

        let expected = app.configFile.deletingLastPathComponent().appending(path: "zdotdir").path(percentEncoded: false)
        sleep(3)
        let written = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? "<none>"
        let screen = app.element("smalti.terminal").value as? String ?? ""
        XCTAssertEqual(written, "\(expected)|\(XCUIApplication.tmuxGuard)|1\n", "screen: \(screen.suffix(600))")
    }
}
