/// HTTP requests that change something in a cloud provider's API (the PocketOS incident): `curl`, `wget`, HTTPie
/// or `xh` against a provider host with a method other than GET or HEAD.
struct ProviderAPIRule: DestructiveCommandRule {
    private static let providers: [(pattern: String, name: String)] = [
        ("backboard.railway.app", "Railway"), ("backboard.railway.com", "Railway"), ("api.supabase.com", "Supabase"),
        ("api.vercel.com", "Vercel"), ("api.netlify.com", "Netlify"), ("api.fly.io", "Fly"),
        ("api.machines.dev", "Fly"), ("api.render.com", "Render"), ("api.heroku.com", "Heroku"),
        ("api.digitalocean.com", "DigitalOcean"), ("api.cloudflare.com", "Cloudflare"), ("console.neon.tech", "Neon"),
        ("api.planetscale.com", "PlanetScale"), ("*.amazonaws.com", "AWS"), ("*.googleapis.com", "Google Cloud"),
        ("management.azure.com", "Azure"),
    ]

    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard let program = command.program, let request = HTTPRequestWords.request(program, command.arguments),
            !["GET", "HEAD"].contains(request.method),
            let provider = Self.provider(of: request.host, extra: context.settings.providerAPIHosts)
        else { return nil }
        return GuardFinding(rule: "API de \(provider) (\(request.method))", environment: .undetermined)
    }

    private static func provider(of host: String, extra: [String]) -> String? {
        if let known = providers.first(where: { HostPattern.matches($0.pattern, host) }) { return known.name }
        return extra.contains { HostPattern.matches($0, host) } ? host : nil
    }
}

/// The method and host of an HTTP client's command line.
enum HTTPRequestWords {
    struct Request: Equatable {
        let method: String
        let host: String
    }

    private static let methods: Set<String> = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

    static func request(_ program: String, _ arguments: [String]) -> Request? {
        switch program {
        case "curl": curl(arguments)
        case "wget": wget(arguments)
        case "http", "https", "xh", "xhs": httpie(arguments)
        default: nil
        }
    }

    /// curl's short options that take a value (`-X DELETE`, `-XDELETE`, `-d@x`), and what some of them mean.
    private static let curlShortWithValue: Set<Character> = [
        "X", "d", "F", "T", "H", "u", "o", "A", "e", "b", "c", "D", "E", "K", "r", "w", "x", "y", "Y", "z", "m", "C",
        "U", "Q",
    ]
    private static let curlLongData: Set<String> = [
        "--data", "--data-raw", "--data-binary", "--data-urlencode", "--data-ascii", "--json", "--form",
        "--form-string",
    ]

    /// What a curl command line asks for, its grouped short options included (`-sX DELETE`, review 1).
    private struct CurlRequest {
        var method: String?
        var sendsData = false
        var uploads = false
        var isGet = false
        var isHead = false

        var resolved: String {
            if let method { return method.uppercased() }
            if isGet { return "GET" }
            if isHead { return "HEAD" }
            if uploads { return "PUT" }
            return sendsData ? "POST" : "GET"
        }
    }

    private static func curl(_ arguments: [String]) -> Request? {
        guard let host = arguments.lazy.compactMap(hostOfURL).first else { return nil }
        var request = CurlRequest()
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            if word.hasPrefix("--") {
                index += curlLong(word, next: next, into: &request)
            } else if word.hasPrefix("-"), word.count > 1 {
                index += curlShort(Array(word.dropFirst()), next: next, into: &request)
            } else {
                index += 1
            }
        }
        return Request(method: request.resolved, host: host)
    }

    /// Reads one long option; returns how many words it took.
    private static func curlLong(_ word: String, next: String?, into request: inout CurlRequest) -> Int {
        let name = optionName(word)
        let attached = word.contains("=") ? String(word.drop { $0 != "=" }.dropFirst()) : nil
        switch name {
        case "--request": request.method = attached ?? next
        case "--get": request.isGet = true
        case "--head": request.isHead = true
        case "--upload-file": request.uploads = true
        case let data where curlLongData.contains(data): request.sendsData = true
        default: break
        }
        let takesValue =
            ["--request", "--upload-file", "--header", "--user", "--output"].contains(name)
            || curlLongData.contains(name)
        return takesValue && attached == nil ? 2 : 1
    }

    /// Reads a cluster of short options (`-sSX`); returns how many words it took.
    private static func curlShort(_ cluster: [Character], next: String?, into request: inout CurlRequest) -> Int {
        for (position, option) in cluster.enumerated() {
            switch option {
            case "G": request.isGet = true
            case "I": request.isHead = true
            default: break
            }
            guard curlShortWithValue.contains(option) else { continue }
            let rest = String(cluster[(position + 1)...])
            let value = rest.isEmpty ? next : rest
            switch option {
            case "X": request.method = value
            case "d", "F": request.sendsData = true
            case "T": request.uploads = true
            default: break
            }
            return rest.isEmpty ? 2 : 1
        }
        return 1
    }

    private static func wget(_ arguments: [String]) -> Request? {
        guard let host = arguments.lazy.compactMap(hostOfURL).first else { return nil }
        if let method = explicitMethod(arguments, long: "--method") {
            return Request(method: method, host: host)
        }
        let posts = arguments.contains {
            ["--post-data", "--post-file", "--body-data", "--body-file"].contains(optionName($0))
        }
        return Request(method: posts ? "POST" : "GET", host: host)
    }

    /// `http [METHOD] URL [items]`: without a method, a data item (`name=x`, `name:=1`, `@file`) makes it a POST.
    private static func httpie(_ arguments: [String]) -> Request? {
        let words = arguments.filter { !$0.hasPrefix("-") }
        let method = words.first.map { $0.uppercased() }.flatMap { methods.contains($0) ? $0 : nil }
        let rest = method == nil ? words[...] : words.dropFirst()
        guard let target = rest.first else { return nil }
        let host = hostOfURL(target) ?? String(target.prefix { $0 != "/" && $0 != ":" }).lowercased()
        let hasData = rest.dropFirst().contains { $0.contains("=") && !$0.contains("==") || $0.hasPrefix("@") }
        return Request(method: method ?? (hasData ? "POST" : "GET"), host: host)
    }

    /// `--method DELETE` or `--method=DELETE`.
    private static func explicitMethod(_ arguments: [String], long: String) -> String? {
        for (index, word) in arguments.enumerated() {
            if word == long { return index + 1 < arguments.count ? arguments[index + 1].uppercased() : nil }
            if word.hasPrefix(long + "=") { return String(word.dropFirst(long.count + 1)).uppercased() }
        }
        return nil
    }

    private static func optionName(_ word: String) -> String {
        String(word.prefix { $0 != "=" })
    }

    /// The host of an `http(s)://` URL, lowercased.
    static func hostOfURL(_ word: String) -> String? {
        guard let scheme = word.firstRange(of: "://"), word.lowercased().hasPrefix("http") else { return nil }
        let authority = word[scheme.upperBound...].prefix { !"/?#".contains($0) }
        let hostAndPort = authority.lastIndex(of: "@").map { authority[authority.index(after: $0)...] } ?? authority
        return String(hostAndPort.prefix { $0 != ":" }).lowercased()
    }
}
