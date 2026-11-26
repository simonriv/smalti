import Foundation

/// Finds the lines of a JSONL file that contain a needle, comparing ASCII letters without case, over the raw bytes:
/// only those lines are decoded (F9 search, `memmem` over 4 MB blocks, cancellable between blocks).
public enum JSONLScanner {
    public static let blockSize = 4 * 1_048_576

    public static func lines(
        containing needle: [UInt8], in file: URL, blockSize: Int = blockSize, isCancelled: () -> Bool,
        line: (Data, UInt64) -> Void
    ) throws(JSONLReadError) {
        let folded = needle.map(lowercased)
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: file) } catch { throw JSONLReadError.reading(file, error) }
        defer { try? handle.close() }
        var carry = Data()
        var carryOffset: UInt64 = 0
        while !isCancelled() {
            let block: Data
            do { block = try handle.read(upToCount: blockSize) ?? Data() } catch {
                throw JSONLReadError.reading(file, error)
            }
            guard !block.isEmpty else { break }
            carry.append(block)
            guard let lastNewline = carry.lastIndex(of: JSONLLineReader.newline) else { continue }
            let complete = carry[carry.startIndex...lastNewline]
            emit(Data(complete), base: carryOffset, needle: folded, line: line)
            carryOffset += UInt64(complete.count)
            carry = Data(carry[(lastNewline + 1)...])
        }
        if !carry.isEmpty, !isCancelled() {
            emit(carry + Data([JSONLLineReader.newline]), base: carryOffset, needle: folded, line: line)
        }
    }

    /// The lines of `bytes` (ending in a newline) that contain `needle`; all of them when it is empty.
    private static func emit(_ bytes: Data, base: UInt64, needle: [UInt8], line: (Data, UInt64) -> Void) {
        guard !needle.isEmpty else { return JSONLLineReader.handOver(bytes, from: base, to: line) }
        let lowered = bytes.map(lowercased)
        lowered.withUnsafeBufferPointer { haystack in
            needle.withUnsafeBufferPointer { pattern in
                guard let start = haystack.baseAddress, let target = pattern.baseAddress else { return }
                var position = 0
                while position < haystack.count,
                    let hit = memmem(start + position, haystack.count - position, target, pattern.count)
                {
                    let at = UnsafePointer(hit.assumingMemoryBound(to: UInt8.self)) - start
                    let lineStart = (lowered[..<at].lastIndex(of: JSONLLineReader.newline) ?? -1) + 1
                    let lineEnd = lowered[at...].firstIndex(of: JSONLLineReader.newline) ?? lowered.count
                    let first = bytes.startIndex + lineStart
                    line(Data(bytes[first..<(bytes.startIndex + lineEnd)]), base + UInt64(lineStart))
                    position = lineEnd + 1
                }
            }
        }
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte | 0x20 : byte
    }
}
