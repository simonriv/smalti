import AppKit
import XCTest

/// Spec F5.5 C1, C4, C5, C11 and C12: hovering an image name in `ls`'s output shows the card of `Main.dc.html`; it
/// goes away on typing, scrolling and leaving the word; ⌘Y opens Quick Look.
final class PreviewTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var terminal: XCUIElement { app.element("smalti.terminal") }
    private var terminalText: String { terminal.value as? String ?? "" }
    private var card: XCUIElement { app.element("preview.card") }
    /// Obsidiana's terminal padding (`paddingX`, `paddingY`): where the cell grid starts.
    private let padding = CGVector(dx: 16, dy: 12)

    private var folder: URL!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "smalti-preview-\(UUID().uuidString)")
        let sub = folder.appending(path: "sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Self.png(width: 1440, height: 900).write(to: folder.appending(path: "landing-v3.png"))
        try Self.png(width: 320, height: 200).write(to: folder.appending(path: "hero.png"))
        try Data("not an image\n".utf8).write(to: folder.appending(path: "notes.md"))
        try Self.png(width: 64, height: 48).write(to: sub.appending(path: "other.png"))
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Card

    func testLsShowsCardOnHover() {
        launchPreview()
        list("ls -1")

        hover(row: 1, column: 3)

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "landing-v3.png · 1440×900 · ⌘Y para abrir")
    }

    func testLsSubfolderShowsCard() {
        launchPreview()
        list("ls -1 sub")

        hover(row: 0, column: 2)

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "other.png · 64×48 · ⌘Y para abrir")
    }

    func testNonImageShowsNoCard() {
        launchPreview()
        list("ls -1")

        hover(row: 2, column: 2)

        XCTAssertFalse(card.waitForExistence(timeout: 2))
    }

    func testTypingHidesCard() {
        showCard()

        app.typeText("x")

        XCTAssertTrue(waitForCardToGo())
    }

    func testScrollHidesCard() {
        showCard()

        terminal.scroll(byDeltaX: 0, deltaY: -5)

        XCTAssertTrue(waitForCardToGo())
    }

    func testLeavingWordHidesCard() {
        showCard()

        hover(row: 1, column: 40)

        XCTAssertTrue(waitForCardToGo())
    }

    func testCardGoesUnderTheWord() {
        showCard()

        let word = cellPoint(row: 1, column: 0)
        XCTAssertGreaterThan(card.frame.minY, word.y)
        XCTAssertEqual(card.frame.width, 210, accuracy: 1)
    }

    func testCardFlipsAboveAtBottomEdge() {
        launchPreview()
        app.run(
            "cd '\(folder.path(percentEncoded: false))'; clear; for i in $(seq 1 80); do echo; done; ls -1 hero.png")
        XCTAssertTrue(waitForTerminal(containing: "hero.png\n"))
        let row = rowOf("hero.png")

        hover(row: row, column: 2)

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertLessThan(card.frame.maxY, cellPoint(row: row, column: 0).y)
        XCTAssertGreaterThanOrEqual(card.frame.minY, terminal.frame.minY)
    }

    func testCardStaysInsidePane() {
        launchPreview()
        app.run("cd '\(folder.path(percentEncoded: false))'; clear; printf '%*s\\n' $COLUMNS hero.png")
        XCTAssertTrue(waitForTerminal(containing: "hero.png\n"))
        let columns = Int((terminal.frame.width - 2 * padding.dx) / cellSize.width)

        hover(row: 0, column: columns - 3)

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(card.frame.maxX, terminal.frame.maxX + 1)
    }

    func testHoverFalseShowsNoCard() {
        launchPreview(config: "[preview]\nhover = false\n")
        list("ls -1")

        hover(row: 1, column: 3)

        XCTAssertFalse(card.waitForExistence(timeout: 2))
    }

    func testReduceMotionSkipsFade() {
        launchPreview(reduceMotion: true)
        list("ls -1")

        hover(row: 1, column: 3)

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "sin fundido")
    }

    // MARK: - Helpers

    private func launchPreview(config: String? = nil, reduceMotion: Bool = false) {
        let smalti = XCUIApplication.isolatedSmaltiWithIntegration()
        smalti.launchArguments += ["-SmaltiExposeCellSize", "YES"]
        if reduceMotion { smalti.launchArguments += ["-SmaltiReduceMotion", "YES"] }
        if let config { smalti.writeConfig(config) }
        launch(smalti)
    }

    /// `cd` into the fixtures and run `command` on a clear screen: its output starts on the first row.
    private func list(_ command: String) {
        app.run("cd '\(folder.path(percentEncoded: false))'; clear; \(command)")
        XCTAssertTrue(waitForTerminal(containing: "notes.md") || waitForTerminal(containing: "other.png"))
    }

    private func showCard() {
        launchPreview()
        list("ls -1")
        hover(row: 1, column: 3)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    private var cellSize: CGSize {
        // "celda 8 × 21" (`-SmaltiExposeCellSize`).
        let numbers = terminal.title.split(separator: " ").compactMap { Double($0) }
        return CGSize(width: numbers.first ?? 8, height: numbers.last ?? 21)
    }

    /// The middle of a cell, in screen points.
    private func cellPoint(row: Int, column: Int) -> CGPoint {
        CGPoint(
            x: terminal.frame.minX + padding.dx + (Double(column) + 0.5) * cellSize.width,
            y: terminal.frame.minY + padding.dy + (Double(row) + 0.5) * cellSize.height)
    }

    private func hover(row: Int, column: Int) {
        let point = cellPoint(row: row, column: column)
        let origin = terminal.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: point.x - terminal.frame.minX, dy: point.y - terminal.frame.minY)).hover()
    }

    /// The visible row whose text starts with `text`.
    private func rowOf(_ text: String) -> Int {
        let rows = terminalText.components(separatedBy: "\n")
        return rows.lastIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(text) } ?? 0
    }

    private func waitForTerminal(containing text: String, timeout: TimeInterval = 10) -> Bool {
        waitUntil(timeout: timeout) { self.terminalText.contains(text) }
    }

    private func waitForCardToGo() -> Bool {
        waitUntil(timeout: 3) { !self.card.exists }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(100_000)
        }
        return condition()
    }

    static func png(width: Int, height: Int) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(srgbRed: 0.43, green: 0.29, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
