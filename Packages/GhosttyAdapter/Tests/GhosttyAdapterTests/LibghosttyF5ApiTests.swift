import AppKit
import CoreText
import Foundation
import GhosttyKit
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// F5 T1: `font-codepoint-map` reaches a font registered only for this process (spec F5, risk 1). The fixture
/// `SmaltiProbe.ttf` has one glyph, a filled block at U+E900. With the map the cell is painted; without it libghostty
/// falls back and the block is missing. The proof is pixels: the window's own capture, counted on both runtimes.
@MainActor
@Suite("libghostty APIs for F5", .serialized)
struct LibghosttyF5ApiTests {
    private let work = FileManager.default.temporaryDirectory.appending(path: "smalti-f5-\(UUID())")

    init() throws {
        try TestGhostty.initialize()
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Self.registerProbeFont()
    }

    private static func registerProbeFont() throws {
        let url = try #require(
            Bundle.module.url(forResource: "SmaltiProbe", withExtension: "ttf", subdirectory: "Fixtures"))
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // Already registered by an earlier test of this run is fine: the process keeps it.
        if !registered, let error = error?.takeRetainedValue(), CFErrorGetCode(error) != 105 {
            Issue.record("probe font not registered: \(error)")
        }
    }

    private func runtime(extraConfig: String, name: String) throws -> GhosttyRuntime {
        let text = GhosttyConfigText.render(Theme.obsidian.terminal) + extraConfig
        let config = try GhosttyConfig.load(text: text, writingTo: work.appending(path: "\(name).conf"))
        return try GhosttyRuntime(config: config)
    }

    /// Counts bright pixels of the window after printing U+E900 in a fresh `zsh -f`.
    private func brightPixelsAfterPrintingProbe(runtime: GhosttyRuntime) async throws -> Int {
        let spec = TerminalSessionSpec(
            workingDirectory: try WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -f"),
            environment: ["SMALTI": "1", "PS1": "% "])
        let view = try GhosttySurfaceView(app: runtime.app, spec: spec)
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 120), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = view
        window.orderFrontRegardless()
        defer {
            view.shutDown()
            window.close()
        }
        try type("printf '\\n\\n\\uE900\\uE900\\uE900\\uE900\\n'", in: view)
        await tick(runtime, seconds: 1.5)
        let image = try #require(WindowCapture.image(of: window))
        return Self.brightPixels(in: image)
    }

    private func type(_ command: String, in view: GhosttySurfaceView) throws {
        let surface = try #require(view.surface)
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        command.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
        view.pressReturn()
    }

    private func tick(_ runtime: GhosttyRuntime, seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            ghostty_app_tick(runtime.app)
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func brightPixels(in image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        return stride(from: 0, to: bytes.count, by: 4).count { index in
            Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2]) > 450
        }
    }

    @Test func codepointMapReachesProcessFont() async throws {
        let mapped = try runtime(extraConfig: "font-codepoint-map = U+E900=SmaltiProbe\n", name: "mapped")
        let withMap = try await brightPixelsAfterPrintingProbe(runtime: mapped)
        let plain = try runtime(extraConfig: "", name: "plain")
        let withoutMap = try await brightPixelsAfterPrintingProbe(runtime: plain)

        // Four filled blocks of one cell each: hundreds of extra bright pixels, at any backing scale.
        #expect(withMap > withoutMap + 200, "with map \(withMap), without \(withoutMap)")
    }
}

/// The window's own pixels. `CGWindowListCreateImage` is unavailable to Swift since the macOS 15 SDK but still
/// exported; a process may capture its own windows without the Screen Recording permission.
@MainActor
enum WindowCapture {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func image(of window: NSWindow) -> CGImage? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        // Safe: the symbol has this C signature (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption).
        let create = unsafeBitCast(pointer, to: CreateImage.self)
        let optionIncludingWindow: UInt32 = 1 << 3
        let imageBoundsIgnoreFraming: UInt32 = 1 << 0
        return create(.null, optionIncludingWindow, UInt32(window.windowNumber), imageBoundsIgnoreFraming)?
            .takeRetainedValue()
    }
}
