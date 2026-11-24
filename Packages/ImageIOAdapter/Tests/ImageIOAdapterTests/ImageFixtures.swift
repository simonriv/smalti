import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image files written for one test in a temporary folder, removed when the test ends.
final class ImageFixtures {
    let folder: URL
    /// Noise makes the pixel data as large as the image, so cutting the file really loses pixels.
    var isNoisy = false

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "imageio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func path(_ name: String) -> String { folder.appending(path: name).path }

    @discardableResult
    func image(_ name: String, width: Int, height: Int, type: UTType = .png) throws -> String {
        let url = folder.appending(path: name)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FixtureError.cannotDraw }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if isNoisy { addNoise(to: context, width: width, height: height) }
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw FixtureError.cannotDraw }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotDraw }
        return url.path
    }

    /// A JPEG stored `width × height` with an EXIF orientation (6: shown rotated 90°, as iPhone portraits are saved).
    func orientedJPEG(_ name: String, width: Int, height: Int, orientation: Int) throws -> String {
        let source = try image("plain-\(name).png", width: width, height: height)
        guard let input = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
            let pixels = CGImageSourceCreateImageAtIndex(input, 0, nil)
        else { throw FixtureError.cannotDraw }
        let url = folder.appending(path: name)
        guard
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw FixtureError.cannotDraw }
        CGImageDestinationAddImage(
            destination, pixels, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotDraw }
        return url.path
    }

    func text(_ name: String) throws -> String {
        let url = folder.appending(path: name)
        try Data("not an image\n".utf8).write(to: url)
        return url.path
    }

    /// A real, noisy PNG cut in half: the header (and its size) is intact, half the pixels are gone.
    func truncatedPNG(_ name: String) throws -> String {
        isNoisy = true
        defer { isNoisy = false }
        let full = try image("full-\(name)", width: 400, height: 300)
        let data = try Data(contentsOf: URL(fileURLWithPath: full))
        let url = folder.appending(path: name)
        try data.prefix(data.count / 2).write(to: url)
        return url.path
    }

    private func addNoise(to context: CGContext, width: Int, height: Int) {
        var generator = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let gray = Double(UInt8.random(in: 0...255, using: &generator)) / 255
                context.setFillColor(CGColor(red: gray, green: 1 - gray, blue: gray / 2, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
    }

    enum FixtureError: Error {
        case cannotDraw
    }
}
