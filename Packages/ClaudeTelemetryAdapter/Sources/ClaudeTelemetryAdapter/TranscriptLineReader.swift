import Foundation

/// Reads a transcript from a byte offset in 1 MB blocks and hands over each complete line. A line Claude is still
/// writing (no `\n` yet) is left for the next read, so nothing is lost or read twice.
enum TranscriptLineReader {
    private static let blockSize = 1_048_576
    private static let newline = UInt8(ascii: "\n")

    /// Returns the offset just after the last complete line.
    static func read(_ file: URL, from offset: UInt64, line: (Data) -> Void) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        var consumed = offset
        var pending = Data()
        while let block = try handle.read(upToCount: blockSize), !block.isEmpty {
            pending.append(block)
            guard let last = pending.lastIndex(of: newline) else { continue }
            let complete = pending[pending.startIndex...last]
            for piece in complete.split(separator: newline, omittingEmptySubsequences: true) { line(Data(piece)) }
            consumed += UInt64(complete.count)
            pending = Data(pending[pending.index(after: last)...])
        }
        return consumed
    }
}
