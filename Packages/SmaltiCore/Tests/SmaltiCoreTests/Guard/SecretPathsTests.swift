import SmaltiCore
import Testing

@Suite("Secret paths")
struct SecretPathsTests {
    private let secrets = SecretPaths(home: "/Users/u")

    private func read(_ text: String) -> String? {
        ShellCommandLine.commands(in: text, home: "/Users/u").lazy.compactMap { secrets.secretRead(in: $0) }.first
    }

    @Test(arguments: [
        ".env", "/p/.env", "/p/.env.local", "/p/.env.production", "/p/.env.staging.local", "/p/server.pem",
        "/p/tls.key", "/p/cert.p12", "/p/cert.pfx", "/p/infra/terraform.tfstate", "/p/terraform.tfstate.backup",
        "/Users/u/.ssh/id_rsa", "/p/id_ed25519", "/p/id_ecdsa", "/p/id_dsa", "/p/id_rsa_work", "/Users/u/.netrc",
        "/Users/u/.pgpass", "/p/.npmrc", "/Users/u/.pypirc",
    ])
    func secretNamesAreSecret(path: String) {
        #expect(secrets.isSecret(path, cwd: nil))
    }

    @Test(arguments: [
        "/p/.env.example", "/p/.env.sample", "/p/.env.template", "/p/.env.dist", "/p/.env.defaults",
        "/Users/u/.ssh/id_rsa.pub", "/p/README.md", "/p/src/environment.ts", "/p/.envrc.md", "/p/keys.ts",
    ])
    func examplesAreNotSecret(path: String) {
        #expect(!secrets.isSecret(path, cwd: nil))
    }

    @Test(arguments: [
        "/Users/u/.ssh/config", "/Users/u/.ssh", "/Users/u/.aws/credentials", "/Users/u/.config/gcloud/a.json",
        "/Users/u/.kube/config", "/Users/u/.docker/config.json", "/Users/u/.config/gh/hosts.yml",
        "/Users/u/.railway/config.json", "/Users/u/.supabase/access-token",
    ])
    func homeDirectoriesAreSecret(path: String) {
        #expect(secrets.isSecret(path, cwd: nil))
    }

    @Test func similarHomeDirectoriesAreNot() {
        #expect(!secrets.isSecret("/Users/u/.sshx/a", cwd: nil))
        #expect(!secrets.isSecret("/Users/u/.docker/other.json", cwd: nil))
        #expect(!secrets.isSecret("/Users/other/.ssh/id_rsa.pub", cwd: nil))
    }

    @Test func relativePathsResolveAgainstTheDirectory() {
        #expect(secrets.isSecret(".ssh/config", cwd: "/Users/u"))
        #expect(secrets.isSecret("../.aws/credentials", cwd: "/Users/u/p"))
        #expect(!secrets.isSecret(".ssh/config", cwd: "/tmp"))
    }

    @Test(arguments: [".e*", "*.pem", ".env*", "/p/.env.l?cal", "id_*", "/Users/u/.ssh/*", "*.tfstate"])
    func globThatMayReachSecret(glob: String) {
        #expect(secrets.mayMatchSecret(glob: glob))
    }

    @Test(arguments: ["*.ts", "src/**", "*", "**/*", "*.md", ".github/*"])
    func globThatCannotReachSecret(glob: String) {
        #expect(!secrets.mayMatchSecret(glob: glob))
    }

    @Test(arguments: [
        ("cat .env", ".env"), ("less .env.local", ".env.local"),
        ("head -n 5 config/.env.production", "config/.env.production"),
        ("tail -f .env", ".env"), ("grep KEY .env", ".env"), ("sed -n 1p .env", ".env"), ("awk '{print}' .env", ".env"),
        ("source .env", ".env"), (". ./.env", "./.env"), ("cp .env /tmp/x", ".env"), ("tar czf x.tgz .env", ".env"),
        ("base64 < .env", ".env"), ("xxd .env", ".env"), ("strings .env", ".env"), ("cat \"$(echo x)\" .env", ".env"),
        ("echo $(cat .env)", ".env"), ("cat .e\"n\"v", ".env"), ("cat ~/.ssh/id_rsa", "/Users/u/.ssh/id_rsa"),
        ("cat $HOME/.aws/credentials", "/Users/u/.aws/credentials"), ("cat ${HOME}/.netrc", "/Users/u/.netrc"),
        ("git show HEAD:.env", ".env"), ("bash -c 'cat .env'", ".env"), ("cat --file=.env", ".env"),
        ("python3 -c \"print(open('.env').read())\"", ".env"),
        ("node -e \"require('fs').readFileSync('.env', 'utf8')\"", ".env"),
        ("ruby -e 'puts File.read(\"~/.netrc\")'", "/Users/u/.netrc"), ("cat .e*", ".e*"),
    ])
    func bashReadsAreFound(command: String, path: String) {
        #expect(read(command) == path)
    }

    @Test(arguments: [
        "ls -la .env", "test -f .env", "[ -f .env ]", "rm .env.local", "stat .env", "touch .env", "chmod 600 .env",
        "echo \"rellena .env\"", "cat README.md", "cat .env.example", "cat ~/.ssh/id_rsa.pub", "git status",
        "node -e \"console.log(process.env.HOME)\"", "grep -n foo *",
    ])
    func innocentCommandsPass(command: String) {
        #expect(read(command) == nil)
    }

    @Test func keychainReadIsSecret() {
        #expect(read("security find-generic-password -s x -w") == "llavero")
        #expect(read("security find-internet-password -g -s x") == "llavero")
        #expect(read("security find-generic-password -s x") == nil)
    }
}
