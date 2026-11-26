import Dispatch
import Foundation

/// Tells when a file changes (written, grown, removed or renamed), at most once per `coalescing` window. It follows
/// the path, not the inode: when the file is replaced (Claude rewrites a transcript by renaming a new one over it), it
/// watches the new file. It holds one `O_EVTONLY` descriptor while alive; `cancel()` (or releasing it) closes it.
/// F9 keeps one only while the timeline shows that file, so nothing watches the disk with the panel closed.
public final class FileWatch: @unchecked Sendable {
    // Unchecked: `pending` and `rearmTries` are only touched on `queue`; `source` and `isCancelled` under `lock`.
    private let path: String
    private let delay: DispatchTimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "dev.simonriv.smalti.filewatch")
    private let lock = NSLock()
    private var isCancelled = false
    private var source: (any DispatchSourceFileSystemObject)?
    private var pending = false
    /// Tries left to find the path again after it was removed (a rename lands right after).
    private var rearmTries = 0
    private static let rearmAttempts = 20
    private static let rearmInterval = DispatchTimeInterval.milliseconds(50)

    public init(file: URL, coalescing: Duration, onChange: @escaping @Sendable () -> Void) throws(JSONLReadError) {
        path = file.path(percentEncoded: false)
        let (seconds, attoseconds) = coalescing.components
        delay = .nanoseconds(Int(seconds * 1_000_000_000 + attoseconds / 1_000_000_000))
        self.onChange = onChange
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            guard FileManager.default.fileExists(atPath: path) else { throw .missing(path: path) }
            throw .unreadable(path: path, reason: String(cString: strerror(errno)))
        }
        queue.sync { arm(descriptor) }
    }

    private var cancelled: Bool { lock.withLock { isCancelled } }

    /// On `queue`: watches `descriptor`, which the source closes when cancelled.
    private func arm(_ descriptor: Int32) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                source.cancel()
                self.lock.withLock { self.source = nil }
                self.rearmTries = Self.rearmAttempts
                self.queue.asyncAfter(deadline: .now() + Self.rearmInterval) { [weak self] in self?.rearm() }
            }
            self.tell()
        }
        source.setCancelHandler { close(descriptor) }
        let kept = lock.withLock {
            guard !isCancelled else { return false }
            self.source = source
            return true
        }
        source.resume()
        if !kept { source.cancel() }
    }

    /// On `queue`: the path again, as soon as something is there.
    private func rearm() {
        guard !cancelled, lock.withLock({ source == nil }), rearmTries > 0 else { return }
        rearmTries -= 1
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            queue.asyncAfter(deadline: .now() + Self.rearmInterval) { [weak self] in self?.rearm() }
            return
        }
        arm(descriptor)
        tell()
    }

    /// On `queue`: one notice per coalescing window.
    private func tell() {
        guard !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            pending = false
            if !cancelled { onChange() }
        }
    }

    public func cancel() {
        let current = lock.withLock {
            isCancelled = true
            defer { source = nil }
            return source
        }
        current?.cancel()
    }

    deinit { cancel() }
}
