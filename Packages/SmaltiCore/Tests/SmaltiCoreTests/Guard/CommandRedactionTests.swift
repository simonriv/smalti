import SmaltiCore
import Testing

@Suite("Command redaction")
struct CommandRedactionTests {
    @Test(arguments: [
        ("psql postgres://u:p4ss@h/db", "psql postgres://u:•••@h/db"),
        ("x mongodb+srv://admin:s3cr3t@c.x.net/db", "x mongodb+srv://admin:•••@c.x.net/db"),
        ("curl -H \"Authorization: Bearer abc.def\" x", "curl -H \"Authorization: Bearer •••\" x"),
        ("curl -H 'authorization: bearer abc' x", "curl -H 'authorization: bearer •••' x"),
        ("curl -u user:pw https://x", "curl -u user:••• https://x"),
        ("curl --user user:pw https://x", "curl --user user:••• https://x"),
        ("PGPASSWORD=x psql", "PGPASSWORD=••• psql"), ("GITHUB_TOKEN=ghp_1 gh api", "GITHUB_TOKEN=••• gh api"),
        ("CLIENT_SECRET='a b' run", "CLIENT_SECRET=••• run"), ("STRIPE_KEY=sk_1 node x", "STRIPE_KEY=••• node x"),
        ("db_password=\"x\" y", "db_password=••• y"), ("PATH=/bin ls", "PATH=/bin ls"),
        ("echo postgres://u@h/db", "echo postgres://u@h/db"),
    ])
    func redacts(text: String, expected: String) {
        #expect(CommandRedaction.redacted(text) == expected)
    }

    @Test func redactsTheIncidentToken() {
        #expect(!CommandRedaction.redacted("curl -H \"Authorization: Bearer rw_123\" x").contains("rw_123"))
    }
}
