import AppKit
import XCTest

/// Spec F5.5 C1 and C10: images of the kitty graphics protocol show in a pane, from another program (the spike's
/// emitter) and from `smalti img`, and stay right through scroll, resize and clear.
final class KittyGraphicsTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var terminal: XCUIElement { app.element("smalti.terminal") }
    private var terminalText: String { terminal.value as? String ?? "" }

    /// A solid PNG of a color no theme uses, so its pixels can be counted on screen.
    private static let red = (red: 230, green: 20, blue: 20)
    private static let blue = (red: 20, green: 40, blue: 230)

    private var folder: URL!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "smalti-kitty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: folder)
    }

    func testThirdPartyKittyImageIsDrawn() throws {
        try launchWithEmitter()

        XCTAssertGreaterThan(samples(of: Self.red), 150, "the emitted image is not on screen")
        attachScreenshot("kitty-third-party")
    }

    func testSmaltiImgGridIsDrawn() throws {
        let grid = folder.appending(path: "grid")
        try FileManager.default.createDirectory(at: grid, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png", "d.png"] {
            try Self.png(Self.blue, width: 320, height: 200).write(to: grid.appending(path: name))
        }
        launch(.isolatedSmalti())

        // The panes' `$TMUX` is the isolation guard, not a tmux: inside a real one `smalti img` writes a list.
        app.run("clear; TMUX= smalti img '\(grid.path(percentEncoded: false))'")

        XCTAssertTrue(waitForTerminal(containing: "4 imágenes"), terminalText)
        // The text arrives before the frame that paints the images.
        XCTAssertTrue(waitUntil { self.blobsAcrossTheFirstImageRow(of: Self.blue) == 4 })
        XCTAssertTrue(terminalText.contains("a.png"))
        XCTAssertTrue(terminalText.contains("320×200"))
        attachScreenshot("smalti-img-grid")
    }

    /// F0's render list A9–A11 with an image in the scrollback: it scrolls away and back, survives a resize, and
    /// `clear` takes it off the screen.
    func testImageSurvivesScrollResizeAndClear() throws {
        try launchWithEmitter()
        XCTAssertGreaterThan(samples(of: Self.red), 150)

        app.run("for i in $(seq 1 120); do echo linea-$i; done")
        XCTAssertTrue(waitForTerminal(containing: "linea-120"))
        XCTAssertTrue(waitUntil { self.samples(of: Self.red) < 20 }, "the image did not scroll away")
        terminal.scroll(byDeltaX: 0, deltaY: 4000)
        XCTAssertTrue(waitUntil { self.samples(of: Self.red) > 150 }, "the image did not come back on scroll")
        attachScreenshot("kitty-scrolled-back")

        let window = app.windows["smalti.window"]
        let original = window.frame
        window.typeKey("f", modifierFlags: [.control, .command])
        defer { if window.frame != original { window.typeKey("f", modifierFlags: [.control, .command]) } }
        // Block 3 review I1: the image counts only once the window really is another size.
        XCTAssertTrue(waitUntilSettled(window, awayFrom: original), "the window did not change size")
        XCTAssertTrue(waitUntil { self.samples(of: Self.red) > 150 }, "the image is gone after resizing")
        attachScreenshot("kitty-resized")
        window.typeKey("f", modifierFlags: [.control, .command])
        XCTAssertTrue(waitUntil(timeout: 10) { window.frame == original }, "the window did not come back")

        terminal.scroll(byDeltaX: 0, deltaY: -4000)
        app.run("clear")
        XCTAssertTrue(waitUntil { self.samples(of: Self.red) < 20 }, "clear left the image on screen")
        attachScreenshot("kitty-cleared")
    }

    // MARK: - Launch

    /// The spike's emitter as the pane's shell: prints a line, a 240×120 image, a line, then becomes `zsh -f`.
    private func launchWithEmitter() throws {
        let image = folder.appending(path: "red.png")
        try Self.png(Self.red, width: 240, height: 120).write(to: image)
        let script = folder.appending(path: "emit.zsh")
        try Data(Self.emitter(image: image.path(percentEncoded: false)).utf8).write(to: script)
        launch(.isolatedSmalti(shell: "/bin/zsh -f \(script.path(percentEncoded: false))"))
        XCTAssertTrue(waitForTerminal(containing: "despues de la imagen"), terminalText)
    }

    private static func emitter(image: String) -> String {
        """
        data=$(base64 < '\(image)' | tr -d '\\n')
        print -r -- "antes de la imagen"
        first=1
        while (( ${#data} > 0 )); do
          chunk=${data[1,4096]}; data=${data[4097,-1]}
          (( ${#data} > 0 )) && m=1 || m=0
          if (( first )); then printf '\\e_Ga=T,f=100,q=2,m=%d;%s\\e\\\\' $m $chunk; first=0
          else printf '\\e_Gm=%d;%s\\e\\\\' $m $chunk; fi
        done
        print -r -- ""
        print -r -- "despues de la imagen"
        exec /bin/zsh -f

        """
    }

    /// Drawn in sRGB with CoreGraphics (an `NSBitmapImageRep` filled with `setColor` came out black).
    private static func png(_ color: (red: Int, green: Int, blue: Int), width: Int, height: Int) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(
            CGColor(
                srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    // MARK: - Screen

    /// Points of the pane, every 4 pt, whose color is within 50 per channel of `color`.
    private func samples(of color: (red: Int, green: Int, blue: Int)) -> Int {
        let pane = PanePixels(terminal)
        var count = 0
        for x in stride(from: 0, to: pane.size.width, by: 4) {
            for y in stride(from: 0, to: pane.size.height, by: 4)
            where pane.isClose(to: color, at: CGPoint(x: x, y: y)) {
                count += 1
            }
        }
        return count
    }

    /// Runs of `color` along the row that crosses the first thumbnails: one per image drawn side by side.
    private func blobsAcrossTheFirstImageRow(of color: (red: Int, green: Int, blue: Int)) -> Int {
        let pane = PanePixels(terminal)
        let firstColored = stride(from: 0, to: pane.size.height, by: 2).first { y in
            stride(from: 0, to: pane.size.width, by: 2).contains { pane.isClose(to: color, at: CGPoint(x: $0, y: y)) }
        }
        guard let top = firstColored else { return 0 }
        var blobs = 0
        var inside = false
        for x in stride(from: 0, to: pane.size.width, by: 2) {
            let isColored = pane.isClose(to: color, at: CGPoint(x: x, y: top + 10))
            if isColored && !inside { blobs += 1 }
            inside = isColored
        }
        return blobs
    }

    /// True once the window's frame is not `original` and has stopped changing (the full-screen animation ended).
    private func waitUntilSettled(_ window: XCUIElement, awayFrom original: CGRect) -> Bool {
        guard waitUntil(timeout: 10, { window.frame != original }) else { return false }
        var last = window.frame
        return waitUntil(timeout: 10) {
            usleep(300_000)
            defer { last = window.frame }
            return window.frame == last
        }
    }

    private func waitForTerminal(containing text: String, timeout: TimeInterval = 10) -> Bool {
        waitUntil(timeout: timeout) { self.terminalText.contains(text) }
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: terminal.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The pane as captured now, on whatever display it is; points are relative to the pane's top-left corner.
private struct PanePixels {
    let size: CGSize
    private let bitmap: NSBitmapImageRep?
    private let scale: CGFloat

    init(_ element: XCUIElement) {
        let image = element.screenshot().image
        bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        size = element.frame.size
        scale = CGFloat(bitmap?.pixelsWide ?? 0) / max(size.width, 1)
    }

    func isClose(to color: (red: Int, green: Int, blue: Int), at point: CGPoint) -> Bool {
        guard
            let pixel = bitmap?.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        else { return false }
        let channels = [
            (Int(pixel.redComponent * 255), color.red), (Int(pixel.greenComponent * 255), color.green),
            (Int(pixel.blueComponent * 255), color.blue),
        ]
        return channels.allSatisfy { abs($0.0 - $0.1) <= 50 }
    }
}
