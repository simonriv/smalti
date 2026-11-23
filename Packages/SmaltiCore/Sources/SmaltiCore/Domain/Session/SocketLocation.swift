import Foundation

/// Where this build's IPC socket lives: in its state directory, unless that path is too long for a Unix socket
/// address (a deep home or a sandboxed test runner's container); then a short path in the user's private temporary
/// directory, derived from the state directory: stable for it, distinct between builds, out of other users' reach.
public enum SocketLocation {
    /// Bytes of `sockaddr_un.sun_path` on macOS, terminator included.
    public static let maximumPathBytes = 104

    public static func socketFile(stateDirectory: URL, temporaryDirectory: URL) -> URL {
        let preferred = stateDirectory.appending(path: "smalti.sock")
        guard preferred.path(percentEncoded: false).utf8.count >= maximumPathBytes else { return preferred }
        return temporaryDirectory.appending(
            path: "smalti-\(stableHash(stateDirectory.path(percentEncoded: false))).sock")
    }

    /// FNV-1a, 64 bits, as 16 hex digits: the same for the same directory in every run.
    private static func stableHash(_ text: String) -> String {
        let hash = text.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
