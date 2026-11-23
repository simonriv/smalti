import Foundation

/// Reads a transcript from a byte offset in 1 MB blocks and hands over each complete line. A line Claude is still
/// writing (no `\n` yet) is left for the next read, so nothing is lost or read twice.
enum TranscriptLineReader {
    private static let blockSize = 1_048_576
    private static let newline = UInt8(ascii: "\n")

    /// Where the read stopped (just after the last complete line handed over) and, if it stopped early, why. A
    /// failure halfway keeps the lines already handed over and the offset that matches them.
    struct Outcome {
        let offset: UInt64
        let failure: (any Error)?
    }

    static func read(_ file: URL, from offset: UInt64, line: (Data) -> Void) -> Outcome {
        var consumed = offset
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            var pending = Data()
            while let block = try handle.read(upToCount: blockSize), !block.isEmpty {
                let start = pending.count
                pending.append(block)
                // Only the new block can hold a new line end: an earlier one would have been handed over already.
                guard let lastInBlock = block.lastIndex(of: newline) else { continue }
                let end = start + block.distance(from: block.startIndex, to: lastInBlock) + 1
                for piece in pending[..<end].split(separator: newline, omittingEmptySubsequences: true) {
                    line(Data(piece))
                }
                consumed += UInt64(end)
                pending = Data(pending[end...])
            }
            return Outcome(offset: consumed, failure: nil)
        } catch {
            return Outcome(offset: consumed, failure: error)
        }
    }
}
