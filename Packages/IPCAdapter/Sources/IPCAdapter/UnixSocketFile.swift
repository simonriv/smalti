import Darwin
import Foundation

/// What every Smalti socket server does with its file: check the path fits, claim it from a crashed instance, bind
/// it owner-only and listen.
enum UnixSocketFile {
    static func checkLength(_ path: String) throws(IPCError) {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw .socketFailed(operation: "path longer than a socket address", path: path, code: ENAMETOOLONG)
        }
    }

    /// Fails if a live instance answers on `path`; removes a stale file otherwise.
    static func claim(_ path: String) throws(IPCError) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(probe) }
        var on: Int32 = 1
        setsockopt(probe, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        if connectTo(probe, path: path) == 0 { throw .socketInUse(path: path) }
        unlink(path)
    }

    static func bind(_ fd: Int32, to path: String) throws(IPCError) {
        var address = socketAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw .socketFailed(operation: "bind", path: path, code: errno) }
        guard chmod(path, 0o600) == 0 else { throw .socketFailed(operation: "chmod", path: path, code: errno) }
        guard listen(fd, 16) == 0 else { throw .socketFailed(operation: "listen", path: path, code: errno) }
    }

    static func connectTo(_ fd: Int32, path: String) -> Int32 {
        var address = socketAddress(path)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func socketAddress(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            // Paths longer than sun_path are cut; Smalti's state paths are far shorter.
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        return address
    }

}
