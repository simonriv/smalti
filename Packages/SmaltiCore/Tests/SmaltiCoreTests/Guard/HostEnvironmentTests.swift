import SmaltiCore
import Testing

@Suite("Host environment")
struct HostEnvironmentTests {
    private func settings(production: [String] = [], nonProduction: [String] = []) -> GuardSettings {
        var settings = GuardSettings.standard
        settings.productionHosts = production
        settings.nonProductionHosts = nonProduction
        return settings
    }

    @Test(arguments: [
        "localhost", "127.0.0.1", "127.8.0.3", "::1", "0.0.0.0", "host.docker.internal", "api.localhost", "",
        "/var/run/postgresql", "LOCALHOST",
    ])
    func localHosts(host: String) {
        #expect(HostEnvironment.classify(host: host, settings: .standard).kind == .local)
    }

    @Test func wildcardMatchesOneOrMoreLabels() {
        let qa = settings(nonProduction: ["*.qa.example.com"])

        #expect(HostEnvironment.classify(host: "db.qa.example.com", settings: qa).kind == .nonProduction)
        #expect(HostEnvironment.classify(host: "a.b.qa.example.com", settings: qa).kind == .nonProduction)
        #expect(HostEnvironment.classify(host: "qa.example.com", settings: qa).kind == .production)
        #expect(HostEnvironment.classify(host: "evilqa.example.com", settings: qa).kind == .production)
    }

    @Test func listedProductionNamesTheCause() {
        let result = HostEnvironment.classify(
            host: "db.abc.supabase.co", settings: settings(production: ["db.abc.supabase.co"]))

        #expect(result == DetectedEnvironment(kind: .production, host: "db.abc.supabase.co", cause: .listed))
        #expect(result.detail == nil)
    }

    @Test func productionListWinsOverNonProduction() {
        let both = settings(production: ["db.x.com"], nonProduction: ["db.x.com"])

        #expect(HostEnvironment.classify(host: "db.x.com", settings: both).kind == .production)
    }

    @Test func unknownHostIsProduction() {
        let result = HostEnvironment.classify(host: "db.example.com", settings: .standard)

        #expect(result.kind == .production)
        #expect(result.label == "PROD")
        #expect(result.detail == "host no reconocido")
    }

    @Test func missingHostIsProductionUndetermined() {
        let result = HostEnvironment.classify(host: nil, settings: .standard)

        #expect(result == DetectedEnvironment(kind: .production, host: nil, cause: .undetermined))
        #expect(result.detail == "no determinado")
    }

    @Test func labels() {
        #expect(DetectedEnvironment(kind: .local, host: "localhost", cause: .localHost).label == "local")
        #expect(DetectedEnvironment(kind: .nonProduction, host: "a", cause: .listed).label == "QA/desarrollo")
    }

    @Test func severityOrdersProductionFirst() {
        let local = DetectedEnvironment(kind: .local, host: nil, cause: .localFlag)
        let production = DetectedEnvironment(kind: .production, host: nil, cause: .undetermined)

        #expect(DetectedEnvironment.mostSevere([local, production]) == production)
        #expect(DetectedEnvironment.mostSevere([]) == nil)
    }

    @Test(arguments: [
        ("postgres://u:p@db.x.com:5432/app", "db.x.com"), ("postgresql://db.x.com/app", "db.x.com"),
        ("mysql://root@MySQL.X.com", "mysql.x.com"),
        ("mongodb+srv://u:p@cluster0.x.mongodb.net/db", "cluster0.x.mongodb.net"),
        ("rediss://:pw@cache.x.com:6380", "cache.x.com"), ("libsql://db-x.turso.io", "db-x.turso.io"),
        ("postgres://u@[::1]:5432/x", "::1"), ("postgres:///app", ""), ("postgres://a,b.x.com/db", "a"),
        ("postgres://u:p@w@host.com/db", "host.com"),
    ])
    func databaseURLHost(url: String, host: String) {
        #expect(DatabaseURL.hosts(in: "x \(url) y") == [host])
    }

    @Test func nonDatabaseURLsAreIgnored() {
        #expect(DatabaseURL.hosts(in: "curl https://db.x.com/x").isEmpty)
    }
}
