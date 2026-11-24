import AppKit
import XCTest

/// F5 C2 and C12: "Proteger legibilidad" over the worst desktop, and themes applied live to every window.
final class LegibilityTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    /// Obsidiana's secondary text (`docs/design/README.md`): the faintest token the 4.5:1 rule covers.
    private static let secondaryText = SampledColor(red: 0x8b, green: 0x91, blue: 0x9c)
    private static let minimumContrast = 4.5

    private var whiteDesktop: NSWindow?
    /// Gray patches of known sRGB levels at the left edge of the white desktop, outside Smalti's window: a screenshot
    /// goes through the display's color profile (sRGB 40 reads as 53, 105 as 124), so samples are mapped back.
    private var patches: [(level: Int, center: CGPoint)] = []

    override func tearDown() async throws {
        whiteDesktop?.orderOut(nil)
        whiteDesktop = nil
        try await super.tearDown()
    }

    /// C2: with the default settings over a white desktop, the panel and the strip are dark enough for the theme's
    /// secondary text.
    func testProtectionRaisesPanelOpacityOverWhite() {
        showWhiteDesktop()
        // Before the launch: the window's shadow would fall on the patches.
        let calibration = Calibration(screen: Screenshot(), patches: patches)
        launch(.isolatedSmalti())
        let screen = Screenshot()

        let panel = calibration.trueColor(screen.color(at: insideCorner(of: app.element("smalti.pane"))))
        let strip = calibration.trueColor(screen.color(at: middle(of: app.element("smalti.dragStrip"))))

        XCTAssertGreaterThanOrEqual(
            Self.secondaryText.contrast(with: panel), Self.minimumContrast, "panel \(panel), \(calibration)")
        XCTAssertGreaterThanOrEqual(Self.secondaryText.contrast(with: strip), Self.minimumContrast, "strip \(strip)")
    }

    /// C12: choosing Niebla in `theme.toml` and reloading turns the panels of both windows light, and the shell keeps
    /// running (same PID).
    func testThemeChangeUpdatesTwoWindowsWithoutRelaunch() {
        showWhiteDesktop()
        launch(.isolatedSmalti())
        app.typeKey("n", modifierFlags: .command)
        waitForShells(count: 2)
        app.run("<<<$$ >\"$SMALTI_UITEST_OUT\"")
        let pid = waitForWrittenLine()
        let before = panelLuminances()

        app.writeTheme("[appearance]\ntheme = \"niebla\"\n")
        reloadConfigFromPalette()

        let lighter = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                zip(before, panelLuminances()).allSatisfy { $1 - $0 > 0.4 }
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [lighter], timeout: 10), .completed, "panels \(panelLuminances())")
        app.run("<<<$$ >>\"$SMALTI_UITEST_OUT\"")
        waitForOutput("\(pid)\n\(pid)\n")
    }

    // MARK: - Helpers

    /// A white window over the whole main screen, behind the app (launched next, so it comes to the front).
    private func showWhiteDesktop() {
        guard let screen = NSScreen.main else { return XCTFail("no main screen") }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.isReleasedWhenClosed = false
        addPatches(to: window, screenHeight: screen.frame.height)
        window.orderFrontRegardless()
        whiteDesktop = window
        // Let the window server show it before anything is captured.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
    }

    private func addPatches(to window: NSWindow, screenHeight: CGFloat) {
        let side: CGFloat = 36
        let content = NSView(frame: window.frame)
        content.wantsLayer = true
        patches = stride(from: 0, through: 255, by: 15).enumerated().map { index, level in
            let frame = CGRect(x: 12, y: screenHeight - 80 - CGFloat(index + 1) * side, width: side, height: side)
            let patch = CALayer()
            patch.frame = frame
            let value = CGFloat(level) / 255
            patch.backgroundColor = NSColor(srgbRed: value, green: value, blue: value, alpha: 1).cgColor
            content.layer?.addSublayer(patch)
            return (level, CGPoint(x: frame.midX, y: screenHeight - frame.midY))
        }
        window.contentView = content
    }

    private func panelLuminances() -> [Double] {
        let screen = Screenshot()
        return app.elements("smalti.pane").allElementsBoundByIndex.map {
            screen.color(at: insideCorner(of: $0)).luminance
        }
    }

    /// Away from the prompt (top left) and inside the rounded border.
    private func insideCorner(of element: XCUIElement) -> CGPoint {
        CGPoint(x: element.frame.maxX - 40, y: element.frame.maxY - 40)
    }

    private func middle(of element: XCUIElement) -> CGPoint {
        CGPoint(x: element.frame.midX, y: element.frame.midY)
    }

    private func waitForWrittenLine() -> String {
        let file = outputFile!
        let written = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (try? String(contentsOf: file, encoding: .utf8))?.hasSuffix("\n") == true
            }, object: nil)
        wait(for: [written], timeout: 10)
        return ((try? String(contentsOf: file, encoding: .utf8)) ?? "").trimmingCharacters(in: .newlines)
    }
}

/// The main screen as captured now; points are XCUITest screen coordinates (top-left origin).
private struct Screenshot {
    private let bitmap: NSBitmapImageRep?
    private let scale: CGFloat

    init() {
        let image = XCUIScreen.main.screenshot().image
        bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        // The image's size is already in pixels: element frames are in points of the main screen.
        scale = CGFloat(bitmap?.pixelsWide ?? 0) / max(NSScreen.main?.frame.width ?? 1, 1)
    }

    func color(at point: CGPoint) -> SampledColor {
        guard
            let pixel = bitmap?.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?
                .usingColorSpace(.sRGB)
        else { return SampledColor(red: 0, green: 0, blue: 0) }
        return SampledColor(
            red: Int(pixel.redComponent * 255), green: Int(pixel.greenComponent * 255),
            blue: Int(pixel.blueComponent * 255))
    }
}

/// Maps a screenshot sample back to the sRGB the app painted, per channel, from patches of known gray levels.
private struct Calibration: CustomStringConvertible {
    private let curves: [[(measured: Double, level: Double)]]

    var description: String {
        "green curve "
            + (curves.dropFirst().first ?? []).map { "\(Int($0.level))→\(Int($0.measured))" }.joined(separator: " ")
    }

    init(screen: Screenshot, patches: [(level: Int, center: CGPoint)]) {
        let samples = patches.map { (level: Double($0.level), color: screen.color(at: $0.center)) }
        curves = [\SampledColor.red, \.green, \.blue].map { channel in
            samples.map { (measured: Double($0.color[keyPath: channel]), level: $0.level) }
                .sorted { $0.measured < $1.measured }
        }
    }

    func trueColor(_ sample: SampledColor) -> SampledColor {
        SampledColor(
            red: level(Double(sample.red), curves[0]), green: level(Double(sample.green), curves[1]),
            blue: level(Double(sample.blue), curves[2]))
    }

    private func level(_ measured: Double, _ curve: [(measured: Double, level: Double)]) -> Int {
        guard let upper = curve.firstIndex(where: { $0.measured >= measured }) else {
            return Int(curve.last?.level ?? measured)
        }
        guard upper > 0 else { return Int(curve[upper].level) }
        let (low, high) = (curve[upper - 1], curve[upper])
        let span = max(high.measured - low.measured, 1)
        return Int((low.level + (measured - low.measured) / span * (high.level - low.level)).rounded())
    }
}

/// An sRGB color with the WCAG relative luminance and contrast ratio.
struct SampledColor: CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int

    var luminance: Double {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: SampledColor) -> Double {
        let (light, dark) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    var description: String { String(format: "#%02x%02x%02x", red, green, blue) }
}
