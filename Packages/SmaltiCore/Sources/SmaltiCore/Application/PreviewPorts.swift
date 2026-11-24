import Foundation

/// The image files the preview reads (spec F5.5): what an image is without decoding it, and a small PNG of it. Only
/// ever reads; a path is never opened, run or followed into anything but a regular file.
public protocol ImageFiles: Sendable {
    /// Name and size in pixels, read from the header; a file that is not a regular image throws.
    func describe(_ path: String) async throws(ImagePreviewError) -> ImageDescription
    /// A PNG of the image that fits in `size` (pixels), proportions kept.
    func thumbnail(of path: String, fitting size: Size) async throws(ImagePreviewError) -> Data
}

/// Why an image cannot be previewed, with the path it is about.
public enum ImagePreviewError: Error, Equatable, Sendable {
    case notFound(path: String)
    /// Not a regular file, or not an image ImageIO reads.
    case notImage(path: String)
    /// Over the size limits (spec: 200 MB, 100 megapixels), known from the header.
    case tooLarge(path: String, reason: String)
    case unreadable(path: String, reason: String)
}
