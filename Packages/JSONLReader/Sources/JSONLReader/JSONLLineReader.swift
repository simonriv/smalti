import Foundation

/// Where a read stopped (just after the last complete line handed over) and, if it stopped early, why. A failure
/// halfway keeps the lines already handed over and the offset that matches them.
public struct JSONLReadOutcome: Sendable {
    public let offset: UInt64
    public let failure: (any Error)?
}

/// Reads a JSONL file from a byte offset in 1 MB blocks and hands over each complete line with its offset. A line
/// still being written (no `\n` yet) is left for the next read, so nothing is lost or read twice (F3, shared in F9).
public enum JSONLLineReader {
    static let blockSize = 1_048_576
    static let newline = UInt8(ascii: "\n")

    public static func read(
        _ file: URL, from offset: UInt64, isCancelled: () -> Bool = { false }, line: (Data, UInt64) -> Void
    ) -> JSONLReadOutcome {
        var consumed = offset
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            var pending = Data()
            var reachedEnd = false
            while !reachedEnd, !isCancelled() {
                // Each block's buffers are autoreleased: drained here, not when the whole file is done.
                try autoreleasepool {
                    guard let block = try handle.read(upToCount: blockSize), !block.isEmpty else {
                        reachedEnd = true
                        return
                    }
                    let start = pending.count
                    pending.append(block)
                    // Only the new block can hold a new line end: an earlier one was handed over already.
                    guard let lastInBlock = block.lastIndex(of: newline) else { return }
                    let end = start + block.distance(from: block.startIndex, to: lastInBlock) + 1
                    handOver(pending[..<end], from: consumed, to: line)
                    consumed += UInt64(end)
                    pending = Data(pending[end...])
                }
            }
            return JSONLReadOutcome(offset: consumed, failure: nil)
        } catch {
            return JSONLReadOutcome(offset: consumed, failure: error)
        }
    }

    /// The non-empty lines of `bytes` (which ends with a newline), each with its offset in the file.
    static func handOver(_ bytes: Data, from base: UInt64, to line: (Data, UInt64) -> Void) {
        var lineStart = bytes.startIndex
        for index in bytes.indices where bytes[index] == newline {
            if index > lineStart {
                line(
                    Data(bytes[lineStart..<index]), base + UInt64(bytes.distance(from: bytes.startIndex, to: lineStart))
                )
            }
            lineStart = index + 1
        }
    }
}
