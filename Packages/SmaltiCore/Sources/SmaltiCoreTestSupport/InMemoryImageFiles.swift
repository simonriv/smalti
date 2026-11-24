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

    /// Where a held path waits: in `describe` or in `thumbnail`.
    public enum Stage: Sendable {
        case describe
        case thumbnail
    }

    private struct Key: Hashable {
        let path: String
        let stage: Stage
    }

    private let lock = NSLock()
    private let entries: [String: Entry]
    private var held: Set<Key> = []
    private var waiting: [Key: [CheckedContinuation<Void, Never>]] = [:]
    private var watchers: [Key: [CheckedContinuation<Void, Never>]] = [:]
    private var thumbnailedPaths: [String] = []
    private var describedPaths: [String] = []
    private var cancelledPaths: [String] = []

    public init(_ entries: [String: Entry]) {
        self.entries = entries
    }

    public var described: [String] { lock.withLock { describedPaths } }
    public var cancelled: [String] { lock.withLock { cancelledPaths } }
    /// Paths a thumbnail was started for.
    public var thumbnailed: [String] { lock.withLock { thumbnailedPaths } }

    /// Calls for `path` at `stage` wait until `release(path)`.
    public func hold(_ path: String, at stage: Stage = .thumbnail) {
        lock.withLock { _ = held.insert(Key(path: path, stage: stage)) }
    }

    /// Releases `path` at every stage.
    public func release(_ path: String) {
        let continuations = lock.withLock {
            [Stage.describe, .thumbnail].flatMap { stage -> [CheckedContinuation<Void, Never>] in
                let key = Key(path: path, stage: stage)
                held.remove(key)
                return waiting.removeValue(forKey: key) ?? []
            }
        }
        continuations.forEach { $0.resume() }
    }

    /// Returns once a call for the held `path` at `stage` is waiting for `release`.
    public func waitUntilRequested(_ path: String, at stage: Stage = .thumbnail) async {
        let key = Key(path: path, stage: stage)
        await withCheckedContinuation { continuation in
            let isWaiting = lock.withLock {
                guard waiting[key]?.isEmpty == false else {
                    watchers[key, default: []].append(continuation)
                    return false
                }
                return true
            }
            if isWaiting { continuation.resume() }
        }
    }

    public func describe(_ path: String) async throws(ImagePreviewError) -> ImageDescription {
        lock.withLock { describedPaths.append(path) }
        await waitIfHeld(Key(path: path, stage: .describe))
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
        lock.withLock { thumbnailedPaths.append(path) }
        await waitIfHeld(Key(path: path, stage: .thumbnail))
        if Task.isCancelled { lock.withLock { cancelledPaths.append(path) } }
        guard case .image = entries[path] else { throw .unreadable(path: path, reason: "cannot decode") }
        return Self.thumbnailData(for: path)
    }

    private func waitIfHeld(_ key: Key) async {
        await withCheckedContinuation { continuation in
            let (isHeld, watching) = lock.withLock { () -> (Bool, [CheckedContinuation<Void, Never>]) in
                guard held.contains(key) else { return (false, []) }
                waiting[key, default: []].append(continuation)
                return (true, watchers.removeValue(forKey: key) ?? [])
            }
            watching.forEach { $0.resume() }
            if !isHeld { continuation.resume() }
        }
    }
}
