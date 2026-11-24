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

    public init(maxBytes: Int = 200_000_000, maxMegapixels: Int = 100) {
        self.maxBytes = maxBytes
        self.maxMegapixels = maxMegapixels
    }

    public func describe(_ path: String) async throws(ImagePreviewError) -> ImageDescription {
        try open(path).description
    }

    public func thumbnail(of path: String, fitting size: Size) async throws(ImagePreviewError) -> Data {
        let opened = try open(path)
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                opened.source, 0, Self.thumbnailOptions(Self.maxPixelSize(of: opened.description, fitting: size)))
        else { throw .unreadable(path: path, reason: "ImageIO could not decode it") }
        return try Self.png(image, path: path)
    }

    private struct Opened {
        let source: CGImageSource
        let description: ImageDescription
    }

    private func open(_ path: String) throws(ImagePreviewError) -> Opened {
        try checkFile(path)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            CGImageSourceGetType(source) != nil,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw .notImage(path: path) }
        let megapixels = Int64(width) * Int64(height) / 1_000_000
        guard megapixels <= maxMegapixels else {
            throw .tooLarge(path: path, reason: "\(megapixels) megapixels (max \(maxMegapixels))")
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return Opened(
            source: source,
            description: ImageDescription(path: path, name: name, pixelWidth: width, pixelHeight: height))
    }

    /// `stat` follows links without opening anything, so a FIFO or a device never blocks or streams.
    private func checkFile(_ path: String) throws(ImagePreviewError) {
        var info = stat()
        guard stat(path, &info) == 0 else {
            if errno == ENOENT || errno == ENOTDIR { throw .notFound(path: path) }
            throw .unreadable(path: path, reason: String(cString: strerror(errno)))
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw .notImage(path: path) }
        guard access(path, R_OK) == 0 else { throw .unreadable(path: path, reason: "permission denied") }
        guard info.st_size <= maxBytes else {
            throw .tooLarge(path: path, reason: "\(info.st_size) bytes (max \(maxBytes))")
        }
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
