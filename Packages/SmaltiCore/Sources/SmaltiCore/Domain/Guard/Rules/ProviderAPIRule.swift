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

    private static let curlData: Set<String> = [
        "-d", "--data", "--data-raw", "--data-binary", "--data-urlencode", "--data-ascii", "--json", "-F", "--form",
        "--form-string",
    ]

    private static func curl(_ arguments: [String]) -> Request? {
        guard let host = arguments.lazy.compactMap(hostOfURL).first else { return nil }
        if let method = explicitMethod(arguments, short: "-X", long: "--request") {
            return Request(method: method, host: host)
        }
        if arguments.contains("-G") || arguments.contains("--get") { return Request(method: "GET", host: host) }
        if arguments.contains("-I") || arguments.contains("--head") { return Request(method: "HEAD", host: host) }
        if arguments.contains("-T") || arguments.contains("--upload-file") { return Request(method: "PUT", host: host) }
        let sendsData = arguments.contains { word in curlData.contains { word == $0 || word.hasPrefix($0 + "=") } }
        return Request(method: sendsData ? "POST" : "GET", host: host)
    }

    private static func wget(_ arguments: [String]) -> Request? {
        guard let host = arguments.lazy.compactMap(hostOfURL).first else { return nil }
        if let method = explicitMethod(arguments, short: nil, long: "--method") {
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

    /// `-X DELETE`, `-XDELETE`, `--request DELETE`, `--request=DELETE`.
    private static func explicitMethod(_ arguments: [String], short: String?, long: String) -> String? {
        for (index, word) in arguments.enumerated() {
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            if word == long || word == short { return next?.uppercased() }
            if word.hasPrefix(long + "=") { return String(word.dropFirst(long.count + 1)).uppercased() }
            if let short, word.hasPrefix(short), word.count > short.count {
                return String(word.dropFirst(short.count)).uppercased()
            }
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
