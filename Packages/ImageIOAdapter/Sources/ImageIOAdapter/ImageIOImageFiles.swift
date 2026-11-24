import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SmaltiCore

/// `ImageFiles` with ImageIO (spec F5.5). A path must be, after following links, a regular readable file under
/// `maxBytes`; its size comes from the header, and an image over `maxMegapixels` is refused before any pixel is
/// decoded. Thumbnails are subsampled by ImageIO to the box, never decoded at full size. Only reads.
public struct ImageIOImageFiles: ImageFiles {
    private let maxBytes: Int
    private let maxMegapixels: Int
    /// One decode at a time across every caller of this instance (final review I3): ImageIO cannot stop a decode once
    /// started, so a mouse moving over large images must not start several at once.
    private let gate = DecodeGate()

    public init(maxBytes: Int = 200_000_000, maxMegapixels: Int = 100) {
        self.maxBytes = maxBytes
        self.maxMegapixels = maxMegapixels
    }

    public func describe(_ path: String) async throws(ImagePreviewError) -> ImageDescription {
        try open(path).description
    }

    public func thumbnail(of path: String, fitting size: Size) async throws(ImagePreviewError) -> Data {
        try await gate.run(path) { () throws(ImagePreviewError) -> Data in
            let opened = try open(path)
            guard
                let image = CGImageSourceCreateThumbnailAtIndex(
                    opened.source, 0, Self.thumbnailOptions(Self.maxPixelSize(of: opened.description, fitting: size)))
            else { throw .unreadable(path: path, reason: "ImageIO could not decode it") }
            return try Self.png(image, path: path)
        }
    }

    /// The open file and ImageIO's source over it; the descriptor lives as long as the source reads through it.
    private final class Opened {
        let source: CGImageSource
        let description: ImageDescription
        private let descriptor: Int32

        init(source: CGImageSource, description: ImageDescription, descriptor: Int32) {
            self.source = source
            self.description = description
            self.descriptor = descriptor
        }

        deinit { close(descriptor) }
    }

    /// Opens once, checks that very file, and hands ImageIO the same descriptor (`/dev/fd/N`): a file swapped for a
    /// FIFO or a device after the check is never what ImageIO reads (block 2 review m2).
    private func open(_ path: String) throws(ImagePreviewError) -> Opened {
        let descriptor = try openChecked(path)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "/dev/fd/\(descriptor)") as CFURL, nil),
            CGImageSourceGetType(source) != nil,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            close(descriptor)
            throw .notImage(path: path)
        }
        // EXIF 5–8 turn the image a quarter: it is shown (and its thumbnail made) with the sides swapped.
        let isTurned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        let (width, height) = isTurned ? (storedHeight, storedWidth) : (storedWidth, storedHeight)
        let pixels = Int64(width) * Int64(height)
        let maxPixels = Int64(maxMegapixels) * 1_000_000
        guard pixels <= maxPixels else {
            close(descriptor)
            throw .tooLarge(path: path, reason: "\(pixels) pixels (max \(maxPixels))")
        }
        let name = String(path.split(separator: "/").last ?? "")
        let description = ImageDescription(path: path, name: name, pixelWidth: width, pixelHeight: height)
        return Opened(source: source, description: description, descriptor: descriptor)
    }

    /// `O_NONBLOCK`: opening a FIFO or a device returns at once; `fstat` on the descriptor then refuses it.
    private func openChecked(_ path: String) throws(ImagePreviewError) -> Int32 {
        let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ENOTDIR { throw .notFound(path: path) }
            throw .unreadable(path: path, reason: String(cString: strerror(errno)))
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw .notImage(path: path)
        }
        guard info.st_size <= maxBytes else {
            close(descriptor)
            throw .tooLarge(path: path, reason: "\(info.st_size) bytes (max \(maxBytes))")
        }
        return descriptor
    }

    /// The longest side of the image fitted in `size`, never larger than the image itself.
    private static func maxPixelSize(of image: ImageDescription, fitting size: Size) -> Int {
        let width = Double(max(image.pixelWidth, 1))
        let height = Double(max(image.pixelHeight, 1))
        let scale = min(size.width / width, size.height / height, 1)
        return max(1, Int((max(width, height) * scale).rounded()))
    }

    private static func thumbnailOptions(_ maxPixelSize: Int) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
    }

    private static func png(_ image: CGImage, path: String) throws(ImagePreviewError) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw .unreadable(path: path, reason: "cannot create a PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw .unreadable(path: path, reason: "cannot write a PNG")
        }
        return data as Data
    }
}

/// Runs one decode at a time. A request cancelled while it waited its turn ends without decoding.
private actor DecodeGate {
    func run(_ path: String, _ work: () throws(ImagePreviewError) -> Data) throws(ImagePreviewError) -> Data {
        guard !Task.isCancelled else { throw .unreadable(path: path, reason: "cancelled") }
        return try work()
    }
}
