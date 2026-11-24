import Foundation
import SmaltiCore

/// `ImageFiles` over a dictionary of paths. Thumbnails can be held until released, to test what happens to a slow
/// one; every call is counted.
public final class InMemoryImageFiles: ImageFiles, @unchecked Sendable {
    public enum Entry: Sendable {
        case image(width: Int, height: Int)
        case text
        case tooLarge
        case unreadable
        /// Describes fine but its pixels cannot be decoded.
        case broken(width: Int, height: Int)
    }

    /// A PNG signature plus the path, so tests can tell thumbnails apart.
    public static func thumbnailData(for path: String) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(path.utf8)
    }

    private let lock = NSLock()
    private let entries: [String: Entry]
    private var held: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var watchers: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var describedPaths: [String] = []
    private var cancelledPaths: [String] = []

    public init(_ entries: [String: Entry]) {
        self.entries = entries
    }

    public var described: [String] { lock.withLock { describedPaths } }
    public var cancelled: [String] { lock.withLock { cancelledPaths } }

    /// Thumbnails of `path` wait until `release(path)`.
    public func hold(_ path: String) { lock.withLock { _ = held.insert(path) } }

    public func release(_ path: String) {
        let continuations = lock.withLock {
            held.remove(path)
            return waiting.removeValue(forKey: path) ?? []
        }
        continuations.forEach { $0.resume() }
    }

    /// Returns once a thumbnail of the held `path` is waiting for `release`.
    public func waitUntilRequested(_ path: String) async {
        await withCheckedContinuation { continuation in
            let isWaiting = lock.withLock {
                guard waiting[path]?.isEmpty == false else {
                    watchers[path, default: []].append(continuation)
                    return false
                }
                return true
            }
            if isWaiting { continuation.resume() }
        }
    }

    public func describe(_ path: String) async throws(ImagePreviewError) -> ImageDescription {
        lock.withLock { describedPaths.append(path) }
        let name = String(path.split(separator: "/").last ?? "")
        switch entries[path] {
        case .image(let width, let height), .broken(let width, let height):
            return ImageDescription(path: path, name: name, pixelWidth: width, pixelHeight: height)
        case .text: throw .notImage(path: path)
        case .tooLarge: throw .tooLarge(path: path, reason: "over 100 megapixels")
        case .unreadable: throw .unreadable(path: path, reason: "permission denied")
        case nil: throw .notFound(path: path)
        }
    }

    public func thumbnail(of path: String, fitting size: Size) async throws(ImagePreviewError) -> Data {
        await waitIfHeld(path)
        if Task.isCancelled { lock.withLock { cancelledPaths.append(path) } }
        guard case .image = entries[path] else { throw .unreadable(path: path, reason: "cannot decode") }
        return Self.thumbnailData(for: path)
    }

    private func waitIfHeld(_ path: String) async {
        await withCheckedContinuation { continuation in
            let (isHeld, watching) = lock.withLock { () -> (Bool, [CheckedContinuation<Void, Never>]) in
                guard held.contains(path) else { return (false, []) }
                waiting[path, default: []].append(continuation)
                return (true, watchers.removeValue(forKey: path) ?? [])
            }
            watching.forEach { $0.resume() }
            if !isHeld { continuation.resume() }
        }
    }
}
