import SmaltiCore
import Testing

@Suite("Secret deny rules")
struct SecretDenyRulesTests {
    private let rules = SecretDenyRules.rules(home: "/Users/u")

    @Test func projectRulesAreRelativeAtAnyDepth() {
        #expect(
            rules.prefix(22) == [
                "Read(**/.env)", "Read(**/.env.local)", "Read(**/.env.*.local)", "Read(**/.env.production)",
                "Read(**/.env.development)", "Read(**/.env.staging)", "Read(**/.env.test)", "Read(**/*.pem)",
                "Read(**/*.key)", "Read(**/*.p12)", "Read(**/*.pfx)", "Read(**/*.tfstate)", "Read(**/*.tfstate.backup)",
                "Read(**/.env.preview)", "Read(**/.npmrc)", "Read(**/.pypirc)", "Read(**/.netrc)", "Read(**/.pgpass)",
                "Read(**/id_rsa)", "Read(**/id_ed25519)", "Read(**/id_ecdsa)", "Read(**/id_dsa)",
            ])
    }

    @Test func homeRulesAreAbsoluteWithDoubleSlash() {
        #expect(
            rules.dropFirst(22) == [
                "Read(//Users/u/.ssh/**)", "Read(//Users/u/.aws/**)", "Read(//Users/u/.config/gcloud/**)",
                "Read(//Users/u/.kube/**)", "Read(//Users/u/.config/gh/**)", "Read(//Users/u/.railway/**)",
                "Read(//Users/u/.supabase/**)", "Read(//Users/u/.docker/config.json)", "Read(//Users/u/.netrc)",
                "Read(//Users/u/.pgpass)", "Read(//Users/u/.npmrc)", "Read(//Users/u/.pypirc)",
            ])
    }

    @Test func hasNoTildeAndNoDuplicates() {
        #expect(rules.count == 34)
        #expect(Set(rules).count == rules.count)
        #expect(!rules.contains { $0.contains("~") })
    }

    @Test func homeWithTrailingSlashGivesTheSameRules() {
        #expect(SecretDenyRules.rules(home: "/Users/u/") == rules)
    }
}
