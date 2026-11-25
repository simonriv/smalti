/// Turns a path into an absolute one without touching the disk: joins it to the directory, then folds `.` and `..`.
/// A relative path without a directory stays relative (folded).
enum GuardPathResolver {
    static func absolute(_ path: String, cwd: String?) -> String {
        let joined = path.hasPrefix("/") || cwd == nil ? path : "\(cwd ?? "")/\(path)"
        return fold(joined)
    }

    static func fold(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                if let last = parts.last, last != ".." { parts.removeLast() } else if !isAbsolute { parts.append(part) }
            default: parts.append(part)
            }
        }
        let body = parts.joined(separator: "/")
        return isAbsolute ? "/" + body : body
    }
}
