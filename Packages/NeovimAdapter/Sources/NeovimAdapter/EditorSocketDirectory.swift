import Darwin
import Foundation

/// Where Smalti's Neovims listen. It sits in `/tmp` (a socket path holds 104 bytes; `$TMPDIR` is too long), so the
/// folder is trusted only if it is a real folder of this user, mode 0700; anything else (a link, another user's
/// folder) is left alone and a fresh private folder is made instead (final review).
public enum EditorSocketDirectory {
    static let privateMode: mode_t = 0o700

    public static func prepare(_ preferred: String) -> String {
        _ = mkdir(preferred, privateMode)
        var info = stat()
        guard lstat(preferred, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid() else {
            return freshFolder() ?? preferred
        }
        if info.st_mode & 0o777 != privateMode { _ = chmod(preferred, privateMode) }
        return preferred
    }

    /// A new `/private/tmp/smalti-XXXXXX`, mode 0700 (`mkdtemp`).
    private static func freshFolder() -> String? {
        var template = Array("/private/tmp/smalti-XXXXXX".utf8CString)
        // Safe: `template` is a NUL-terminated buffer that `mkdtemp` fills in place; the name is copied out before
        // the buffer's scope ends.
        return template.withUnsafeMutableBufferPointer { buffer in
            mkdtemp(buffer.baseAddress).map { String(cString: $0) }
        }
    }
}
