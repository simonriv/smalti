import AppKit
import XCTest

/// F5.5 C3, on demand (`TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh PreviewLatencyTests`): the card shows at most
/// 150 ms after the 300 ms wait for a 4000×3000 PNG. The app writes each load's time (`-SmaltiPreviewTimings`); the
/// test prints p50 and p95 and checks p95.
final class PreviewLatencyTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private static let samples = 12
    private let padding = CGVector(dx: 16, dy: 12)
    private var folder: URL!
    private var timingsFile: URL!

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SMALTI_MEASURE"] == "1", "measurements run on demand")
        folder = FileManager.default.temporaryDirectory.appending(path: "smalti-preview-latency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.png", "b.png"] {
            try Self.noisyPNG(width: 4000, height: 3000).write(to: folder.appending(path: name))
        }
        timingsFile = folder.appending(path: "timings.txt")
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: folder)
    }

    func testCardShowsWithin150MsAfterTheWait() throws {
        let smalti = XCUIApplication.isolatedSmaltiWithIntegration()
        smalti.launchArguments += [
            "-SmaltiExposeCellSize", "YES", "-SmaltiPreviewTimings", timingsFile.path(percentEncoded: false),
        ]
        launch(smalti)
        app.run("cd '\(folder.path(percentEncoded: false))'; clear; ls -1")
        let card = app.element("preview.card")
        XCTAssertTrue(waitUntil { (self.app.element("smalti.terminal").value as? String ?? "").contains("b.png") })

        for sample in 0..<Self.samples {
            hover(row: sample % 2, column: 1)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            hover(row: 10, column: 40)
            XCTAssertTrue(waitUntil { !card.exists })
        }

        let times = try String(contentsOf: timingsFile, encoding: .utf8).split(separator: "\n").compactMap {
            Double($0)
        }.sorted()
        XCTAssertGreaterThanOrEqual(times.count, Self.samples)
        let p50 = times[times.count / 2]
        let p95 = times[Int((Double(times.count) * 0.95).rounded(.up)) - 1]
        print("PREVIEW-LATENCY p50 \(p50) ms p95 \(p95) ms over \(times.count) loads")
        XCTAssertLessThanOrEqual(p95, 150)
    }

    private func hover(row: Int, column: Int) {
        let terminal = app.element("smalti.terminal")
        let numbers = terminal.title.split(separator: " ").compactMap { Double($0) }
        let cell = CGSize(width: numbers.first ?? 8, height: numbers.last ?? 21)
        let offset = CGVector(
            dx: padding.dx + (Double(column) + 0.5) * cell.width, dy: padding.dy + (Double(row) + 0.5) * cell.height)
        terminal.coordinate(withNormalizedOffset: .zero).withOffset(offset).hover()
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(50_000)
        }
        return condition()
    }

    /// Random pixels: as large to decode as a photo, not a solid color ImageIO reduces for free.
    private static func noisyPNG(width: Int, height: Int) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let pixels = context.data
        else { throw CocoaError(.fileWriteUnknown) }
        arc4random_buf(pixels, width * height * 4)
        guard let image = context.makeImage(),
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
