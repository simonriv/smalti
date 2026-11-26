import Dispatch
import Foundation

/// Tells when a file changes (written, grown, removed or renamed), at most once per `coalescing` window. It holds one
/// `O_EVTONLY` descriptor while alive; `cancel()` (or releasing it) closes it. F9 keeps one only while the timeline
/// shows that file, so nothing watches the disk with the panel closed.
public final class FileWatch: @unchecked Sendable {
    // Unchecked: `source` and `pending` are only touched on `queue`, `isCancelled` under `lock`.
    private let source: any DispatchSourceFileSystemObject
    private let queue = DispatchQueue(label: "dev.simonriv.smalti.filewatch")
    private let lock = NSLock()
    private var isCancelled = false
    private var pending = false

    public init(file: URL, coalescing: Duration, onChange: @escaping @Sendable () -> Void) throws(JSONLReadError) {
        let descriptor = open(file.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            let path = file.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else { throw .missing(path: path) }
            throw .unreadable(path: path, reason: String(cString: strerror(errno)))
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        let delay = DispatchTimeInterval.nanoseconds(
            Int(
                coalescing.components.seconds * 1_000_000_000
                    + coalescing.components.attoseconds / 1_000_000_000))
        source.setEventHandler { [weak self] in
            guard let self, !self.pending else { return }
            self.pending = true
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.pending = false
                if !self.cancelled { onChange() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    private var cancelled: Bool { lock.withLock { isCancelled } }

    public func cancel() {
        let first = lock.withLock {
            defer { isCancelled = true }
            return !isCancelled
        }
        if first { source.cancel() }
    }

    deinit { cancel() }
}
