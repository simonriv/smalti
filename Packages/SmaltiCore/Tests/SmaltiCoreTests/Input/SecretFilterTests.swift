import SmaltiCore
import Testing

@Suite("SecretFilter")
struct SecretFilterTests {
    @Test(arguments: [
        "export OPENAI_API_KEY=abc123", "FOO_TOKEN=x npm publish", "PASSWORD=hunter2 ./run", "DB_PASSWORD=x make",
        "AWS_SECRET=y aws s3 ls",
    ])
    func sensitiveAssignments(command: String) {
        #expect(SecretFilter.isSensitive(command))
    }

    // Review I6: assignments are usually quoted.
    @Test(arguments: ["export API_KEY=\"abc123\"", "export OPENAI_API_KEY='abc'", "DB_PASSWORD=\"p a s s\" make"])
    func sensitiveQuotedAssignments(command: String) {
        #expect(SecretFilter.isSensitive(command))
    }

    @Test func quotedAssignmentIsRedactedWhole() {
        #expect(SecretFilter.redacted("export API_KEY=\"abc 123\" && run") == "export API_KEY=«redactado» && run")
    }

    @Test func authorizationSchemeWordIsNotTheSecret() {
        #expect(!SecretFilter.redacted("curl -H 'Authorization: token abc123' x").contains("abc123"))
    }

    @Test func sensitiveHeaders() {
        #expect(SecretFilter.isSensitive("curl -H \"Authorization: Bearer abc.def\" https://api.example.com"))
    }

    @Test(arguments: [
        "echo sk-proj-AbCdEfGhIjKlMnOpQrStUv", "git clone https://ghp_abcdefghijklmnopqrstuvwxyz0123@github.com/x",
        "gh auth login --with-token github_pat_11ABCDEFG0123456789_abcdefghijk",
        "curl -d token=xoxb-1234567890-abcdefghij https://slack.com", "echo AKIAABCDEFGHIJKLMNOP",
        "http :8080 X-Token:eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc_DEF-123",
    ])
    func sensitiveTokenShapes(command: String) {
        #expect(SecretFilter.isSensitive(command))
    }

    @Test func sensitiveURLCredentials() {
        #expect(SecretFilter.isSensitive("psql postgres://admin:s3cret@db.local:5432/app"))
    }

    @Test(arguments: [
        "echo KEY", "cat token_list.txt", "ls ~/.ssh", "git commit -m \"rotate API key handling\"",
        "open https://github.com/simonriv/smalti", "export EDITOR=nvim", "grep -r password src",
        // Review I5: words that merely contain a token prefix.
        "git checkout task-refactor-history-index", "npm run disk-usage-report-all", "echo maxoxb-thing",
        "ls theyJson.txt", "cat SKAKIAABCDEFGHIJKLMNOPQ",
    ])
    func notSensitiveLookalikes(command: String) {
        #expect(!SecretFilter.isSensitive(command))
    }

    @Test func redactionKeepsTheKeyName() {
        #expect(
            SecretFilter.redacted("export OPENAI_API_KEY=abc123 && run") == "export OPENAI_API_KEY=«redactado» && run")
    }

    @Test func redactionReplacesTokensAndURLPasswords() {
        #expect(SecretFilter.redacted("echo AKIAABCDEFGHIJKLMNOP") == "echo «redactado»")
        #expect(SecretFilter.redacted("psql postgres://admin:s3cret@db") == "psql postgres://admin:«redactado»@db")
    }

    @Test func redactionKeepsCleanText() {
        #expect(SecretFilter.redacted("ls -la") == "ls -la")
    }
}
