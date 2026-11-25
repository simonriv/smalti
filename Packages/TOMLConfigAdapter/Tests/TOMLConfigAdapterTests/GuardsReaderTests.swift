import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

/// Spec F7.5: `[guards]` in `config.toml`.
@Suite("Guards settings in the TOML")
struct GuardsReaderTests {
    private func parse(_ text: String) throws(ConfigError) -> SmaltiConfig {
        try TOMLConfigParser.parse(text, file: "config.toml")
    }

    @Test func defaultsWhenAbsent() throws {
        #expect(try parse("").guards == .standard)
    }

    @Test func guardsTableReads() throws {
        let guards = try parse(
            """
            [guards]
            production_hosts = ["db.abc.supabase.co"]
            non_production_hosts = ["*.qa.example.com", "db.xyz.supabase.co"]
            provider_api_hosts = ["api.example-cloud.com"]
            """
        ).guards

        #expect(guards.productionHosts == ["db.abc.supabase.co"])
        #expect(guards.nonProductionHosts == ["*.qa.example.com", "db.xyz.supabase.co"])
        #expect(guards.providerAPIHosts == ["api.example-cloud.com"])
    }

    @Test func missingKeysKeepTheirDefault() throws {
        let guards = try parse("[guards]\nproduction_hosts = [\"a\"]\n").guards

        #expect(guards.nonProductionHosts.isEmpty)
        #expect(guards.providerAPIHosts.isEmpty)
    }

    @Test func unknownGuardsKeyRejected() {
        do {
            _ = try parse("[guards]\nprod_hosts = [\"a\"]\n")
            Issue.record("an unknown key was accepted")
        } catch {
            #expect(error.key == "prod_hosts")
        }
    }

    @Test func nonListValueRejected() {
        do {
            _ = try parse("[guards]\nproduction_hosts = \"a\"\n")
            Issue.record("a non-list value was accepted")
        } catch {
            #expect(error.key == "production_hosts")
            #expect(error.line == 2)
        }
    }
}
