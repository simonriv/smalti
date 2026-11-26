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
        let original = [UInt8](bytes)
        let folded = FoldedBlock(original)
        folded.bytes.withUnsafeBufferPointer { haystack in
            needle.withUnsafeBufferPointer { pattern in
                guard let start = haystack.baseAddress, let target = pattern.baseAddress else { return }
                var position = 0
                while position < haystack.count,
                    let hit = memmem(start + position, haystack.count - position, target, pattern.count)
                {
                    let at = UnsafePointer(hit.assumingMemoryBound(to: UInt8.self)) - start
                    let (lineStart, lineEnd, nextFolded) = folded.line(containing: at, in: original)
                    line(Data(original[lineStart..<lineEnd]), base + UInt64(lineStart))
                    position = nextFolded
                }
            }
        }
    }

    static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte | 0x20 : byte
    }
}

/// A block folded as the domain folds the query (`TextFolding`: lowercase, then decomposed and without combining
/// marks): ASCII lowercased; Latin-1 (`0xC3 xx`) and Latin Extended-A (`0xC4`/`0xC5 xx`) letters to their base
/// letter; letters without a decomposition (`Ø`, `Æ`, `Þ`, `Ð`) to their lowercase; combining marks (U+0300–U+036F,
/// `0xCC`/`0xCD xx`) left out. Newlines stay, so a hit's line is found by counting them.
struct FoldedBlock {
    /// `À`…`ÿ` (`0xC3 0x80`…`0xC3 0xBF`) to their base letter; 0 keeps the letter (lowercased below).
    private static let latin1: [UInt8] = Array(
        "aaaaaa\0ceeeeiiii\0nooooo\0\0uuuuy\0\0aaaaaa\0ceeeeiiii\0nooooo\0\0uuuuy\0y".utf8)
    /// U+0100…U+017F to their base letter; 0 keeps the two bytes.
    private static let extendedA: [UInt8] = Array(
        "aaaaaaccccccccdd\0\0eeeeeeeeeegggggggghh\0\0iiiiiiiii\0\0\0jjkk\0llllll\0\0\0\0nnnnnn\0\0\0oooooo\0\0rrrrrrsssssssstttt\0\0uuuuuuuuuuuuwwyyyzzzzzz\0"
            .utf8)
    /// `Æ Ð Ø Þ` and the other uppercase Latin-1 letters without a base: the lowercase is 0x20 further.
    private static let latin1Upper: ClosedRange<UInt8> = 0x80...0x9E
    private static let combiningMarks: ClosedRange<UInt16> = 0xCC80...0xCDAF

    let bytes: [UInt8]
    /// Where each line starts in the folded bytes and in the original ones.
    private let foldedStarts: [Int]
    private let originalStarts: [Int]

    init(_ original: [UInt8]) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(original.count)
        var foldedStarts = [0]
        var originalStarts = [0]
        var index = 0
        while index < original.count {
            let byte = original[index]
            if index + 1 < original.count, let folded = Self.fold(byte, original[index + 1]) {
                bytes += folded
                index += 2
                continue
            }
            bytes.append(JSONLScanner.lowercased(byte))
            index += 1
            if byte == JSONLLineReader.newline {
                foldedStarts.append(bytes.count)
                originalStarts.append(index)
            }
        }
        self.bytes = bytes
        self.foldedStarts = foldedStarts
        self.originalStarts = originalStarts
    }

    /// What a two-byte sequence folds to; nil when it is not one of the folded ranges.
    private static func fold(_ first: UInt8, _ second: UInt8) -> [UInt8]? {
        guard second >= 0x80, second <= 0xBF else { return nil }
        if combiningMarks.contains(UInt16(first) << 8 | UInt16(second)) { return [] }
        switch first {
        case 0xC3:
            let base = latin1[Int(second - 0x80)]
            if base != 0 { return [base] }
            return latin1Upper.contains(second) && second != 0x97 ? [first, second + 0x20] : [first, second]
        case 0xC4, 0xC5:
            let base = extendedA[Int(first - 0xC4) * 64 + Int(second - 0x80)]
            return base != 0 ? [base] : [first, second]
        default: return nil
        }
    }

    /// The original line holding folded position `at` (start, end without the newline) and where the next search
    /// in the folded bytes begins (after that line).
    func line(containing at: Int, in original: [UInt8]) -> (Int, Int, Int) {
        var low = 0
        var high = foldedStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if foldedStarts[middle] <= at { low = middle } else { high = middle - 1 }
        }
        let start = originalStarts[low]
        let end = low + 1 < originalStarts.count ? originalStarts[low + 1] - 1 : original.count
        let next = low + 1 < foldedStarts.count ? foldedStarts[low + 1] : bytes.count
        return (start, end, next)
    }
}
