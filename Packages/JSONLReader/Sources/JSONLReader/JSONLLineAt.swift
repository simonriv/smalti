import Foundation

/// One line read again by its place, to copy a text whole (F9: the timeline keeps excerpts, not texts).
public enum JSONLLineAt {
    public static func line(in file: URL, at offset: UInt64, length: Int) throws(JSONLReadError) -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: length) ?? Data()
            guard data.count == length else {
                throw JSONLReadError.unreadable(
                    path: file.path(percentEncoded: false),
                    reason: "expected \(length) bytes at \(offset), got \(data.count)")
            }
            return data
        } catch let error as JSONLReadError {
            throw error
        } catch {
            throw JSONLReadError.reading(file, error)
        }
    }
}

/// A file's inode and size: a different inode or a smaller size means it was rewritten and must be read again.
public enum JSONLFileIdentity {
    public static func of(_ file: URL) -> (inode: UInt64, size: UInt64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            let size = (attributes[.size] as? NSNumber)?.uint64Value
        else { return nil }
        return (inode, size)
    }
}
