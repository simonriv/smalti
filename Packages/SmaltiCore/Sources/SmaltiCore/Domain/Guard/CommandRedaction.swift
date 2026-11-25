/// Hides what a command carries in clear (spec F7.5, C7): URL passwords, bearer tokens, `-u user:pass` and
/// assignments whose name says password, token, secret or key. Used for the card, notifications, ⌘K and logs.
public enum CommandRedaction {
    public static let mask = "•••"

    public static func redacted(_ text: String) -> String {
        var result = text
        result.replace(/(?i)([a-z][a-z0-9+.\-]*:\/\/[^\s:\/@'"]*):[^\s'"]*@/) { "\($0.output.1):\(mask)@" }
        result.replace(/(?i)((?:authorization|proxy-authorization)\s*:\s*(?:bearer|basic|token|digest)\s+)[^\s'"]+/) {
            "\($0.output.1)\(mask)"
        }
        result.replace(/(?i)(bearer\s+)[^\s'"•]+/) { "\($0.output.1)\(mask)" }
        result.replace(/(?i)((?:apikey|api-key|x-api-key|x-auth-token)\s*:\s*)[^\s'"]+/) { "\($0.output.1)\(mask)" }
        result.replace(/((?:\s|^)(?:-u\s*|--user[\s=]+)[^\s:'"]+):[^\s'"]+/) { "\($0.output.1):\(mask)" }
        result.replace(/((?:^|[\s;&|])(?:mysql|mariadb|mysqldump|mysqladmin)\b[^\n;&|]*?\s-p)([^\s'"]+)/) {
            "\($0.output.1)\(mask)"
        }
        result.replace(/([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'[^']*'|[^\s;&|]+)/) { match in
            isSensitive(String(match.output.1)) ? "\(match.output.1)=\(mask)" : String(match.output.0)
        }
        return result
    }

    private static func isSensitive(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.contains("PASSWORD") || upper.contains("TOKEN") || upper.contains("SECRET")
            || upper.hasSuffix("_KEY") || upper == "KEY" || upper.hasSuffix("_PAT") || upper == "PAT"
            || upper.contains("CREDENTIAL") || (upper.contains("AUTH") && !upper.contains("AUTHOR"))
    }
}
