import SmaltiCore
import Testing

@Suite("Shell command line")
struct ShellCommandLineTests {
    private let home = "/Users/u"

    private func commands(_ text: String) -> [SimpleCommand] {
        ShellCommandLine.commands(in: text, home: home)
    }

    @Test func splitsSeparators() {
        let programs = commands("a && b; c | d || e & f\ng").map(\.program)

        #expect(programs == ["a", "b", "c", "d", "e", "f", "g"])
    }

    @Test func quotedPartsJoinIntoOnePath() {
        let words = commands(#"cat .e"n"v '.env' .env\ x"#).first?.arguments

        #expect(words == [".env", ".env", ".env x"])
    }

    @Test func stripsAssignmentsAndWrappers() {
        let command = commands("DATABASE_URL=postgres://h/db sudo env X=1 npx -y prisma migrate reset").first

        #expect(command?.program == "prisma")
        #expect(command?.arguments == ["migrate", "reset"])
        #expect(command?.assignments["DATABASE_URL"] == "postgres://h/db")
        #expect(command?.assignments["X"] == "1")
    }

    @Test(arguments: [
        ("pnpm dlx drizzle-kit push", "drizzle-kit"), ("yarn exec prisma db push", "prisma"),
        ("npm exec -- prisma db push", "prisma"), ("bunx --bun drizzle-kit push", "drizzle-kit"),
        ("dotenv -e .env.prod -- npm run db:push", "npm"), ("doppler run -- terraform apply", "terraform"),
        ("op run --env-file x -- psql", "psql"), ("infisical run -- railway down", "railway"),
        ("time nohup nice -n 5 command exec terraform destroy", "terraform"),
    ])
    func stripsEveryWrapper(text: String, program: String) {
        #expect(commands(text).first?.program == program)
    }

    @Test func recursesIntoShellC() {
        #expect(commands("bash -c 'terraform destroy'").map(\.program).contains("terraform"))
        #expect(commands(#"eval "supabase db reset""#).map(\.program).contains("supabase"))
        #expect(commands("echo $(cat .env)").map(\.program).contains("cat"))
        #expect(commands("echo `cat .env`").map(\.program).contains("cat"))
        #expect(commands(#"ssh prod 'psql -c "DROP TABLE a"'"#).map(\.program).contains("psql"))
    }

    @Test func nestedSubstitutionKeepsItsArguments() {
        let inner = commands("echo \"$(cat ~/.ssh/id_rsa)\"").first { $0.program == "cat" }

        #expect(inner?.arguments == ["/Users/u/.ssh/id_rsa"])
    }

    @Test func expandsHome() {
        let words = commands("cat ~/.ssh/id_rsa $HOME/.aws/credentials ${HOME}/.netrc ~").first?.arguments

        #expect(words == ["/Users/u/.ssh/id_rsa", "/Users/u/.aws/credentials", "/Users/u/.netrc", "/Users/u"])
    }

    @Test func singleQuotedHomeIsLiteral() {
        #expect(commands("cat '~/.netrc'").first?.arguments == ["~/.netrc"])
    }

    @Test func basenameOfProgram() {
        let command = commands("./node_modules/.bin/drizzle-kit push").first

        #expect(command?.program == "drizzle-kit")
        #expect(command?.arguments == ["push"])
    }

    @Test func redirectionsAreCaptured() {
        let command = commands("base64 < .env > out 2>&1").first

        #expect(command?.redirections == [".env", "out"])
        #expect(command?.arguments == [])
    }

    @Test func attachedRedirectionIsCaptured() {
        #expect(commands("wc -l <.env").first?.redirections == [".env"])
    }

    @Test func unterminatedQuoteIsTolerated() {
        #expect(commands(#"cat ".env"#).first?.arguments == [".env"])
    }

    @Test func emptyAndOnlySpaces() {
        #expect(commands("").isEmpty)
        #expect(commands("   \n ").isEmpty)
    }

    @Test func recursionIsBounded() {
        var text = "terraform destroy"
        for _ in 0..<10 { text = "bash -c \(shellQuoted(text))" }

        let programs = commands(text).map(\.program)

        #expect(programs.count <= 6)
    }

    @Test func rawTextIsTheSimpleCommandSource() {
        let command = commands(#"psql -c "drop table a" && ls"#).first

        #expect(command?.rawText == #"psql -c "drop table a""#)
    }

    @Test func onlyAssignmentsHasNoProgram() {
        let command = commands("FOO=1").first

        #expect(command?.program == nil)
        #expect(command?.assignments["FOO"] == "1")
    }

    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacing("'", with: #"'\''"#) + "'"
    }
}
