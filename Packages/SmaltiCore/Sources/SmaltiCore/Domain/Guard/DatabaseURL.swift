/// Database URLs in text (spec F7.5): `postgres(ql)`, `mysql`, `mariadb`, `mongodb(+srv)`, `redis(s)` and `libsql`.
/// Only the host is kept; credentials never leave this type.
public enum DatabaseURL {
    static let schemes: Set<String> = [
        "postgres", "postgresql", "mysql", "mariadb", "mongodb", "mongodb+srv", "redis", "rediss", "libsql",
    ]

    /// The host of every database URL in `text`, in order (lowercased; `""` for a local socket).
    public static func hosts(in text: String) -> [String] {
        var hosts: [String] = []
        var rest = text[...]
        while let separator = rest.firstRange(of: "://") {
            let scheme = schemeBefore(separator.lowerBound, in: rest)
            if isDatabase(scheme.lowercased()) { hosts.append(host(afterScheme: rest[separator.upperBound...])) }
            rest = rest[separator.upperBound...]
        }
        return hosts
    }

    /// `postgres`, and a driver variant of it (`postgresql+asyncpg`, review 1).
    private static func isDatabase(_ scheme: String) -> Bool {
        schemes.contains(scheme) || scheme.split(separator: "+").first.map { schemes.contains(String($0)) } == true
    }

    /// The host of one URL, or nil when it is not a database URL.
    public static func host(of url: String) -> String? {
        hosts(in: url).first
    }

    private static func schemeBefore(_ end: Substring.Index, in text: Substring) -> Substring {
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            guard character.isLetter || character.isNumber || character == "+" || character == "." || character == "-"
            else { break }
            start = previous
        }
        return text[start..<end]
    }

    private static let authorityEnd: Set<Character> = ["/", "?", "#", " ", "\t", "\n", "\"", "'", ";", "&", "|", ")"]

    private static func host(afterScheme text: Substring) -> String {
        let authority = text.prefix { !authorityEnd.contains($0) }
        let hostAndPort = authority.lastIndex(of: "@").map { authority[authority.index(after: $0)...] } ?? authority
        let first = hostAndPort.split(separator: ",", omittingEmptySubsequences: false).first ?? hostAndPort
        if first.hasPrefix("["), let close = first.firstIndex(of: "]") {
            return String(first[first.index(after: first.startIndex)..<close]).lowercased()
        }
        return String(first.prefix { $0 != ":" }).lowercased()
    }
}
