import Foundation
import SmaltiCore

/// `PathFacts` with `lstat`: what is at a path, without opening it (a FIFO or a device never blocks). A symbolic
/// link is followed one level: its target must not be a link itself (spec F5.6, "Rutas").
public struct FileSystemPathFacts: PathFacts {
    public init() {}

    public func kind(of path: String) async -> PathKind? {
        guard let mode = Self.mode(of: path) else { return nil }
        guard Self.isLink(mode) else { return Self.kind(of: mode) }
        guard let target = Self.target(of: path), let targetMode = Self.mode(of: target), !Self.isLink(targetMode)
        else { return nil }
        return Self.kind(of: targetMode)
    }

    private static func mode(of path: String) -> mode_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_mode : nil
    }

    private static func isLink(_ mode: mode_t) -> Bool { mode & S_IFMT == S_IFLNK }

    private static func kind(of mode: mode_t) -> PathKind {
        mode & S_IFMT == S_IFDIR ? .directory : .file
    }

    /// The link's target as an absolute path (a relative target is relative to the link's folder).
    private static func target(of link: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlink(link, &buffer, Int(PATH_MAX))
        guard count > 0 else { return nil }
        let target = String(decoding: buffer[0..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard !target.hasPrefix("/") else { return target }
        let folder = link.split(separator: "/", omittingEmptySubsequences: false).dropLast().joined(separator: "/")
        return folder + "/" + target
    }
}
