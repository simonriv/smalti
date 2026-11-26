import Foundation
import SmaltiCore
import SmaltiIPCProtocol
import Testing

@testable import smalti

/// What a fake socket does with a guard request.
enum FakeAnswer: Sendable {
    case unreachable
    case timeout
    case closed
    case garbage
    case response(IPCResponse)
}

final class FakeGuardTransport: GuardTransport, @unchecked Sendable {
    // Only one test thread touches it.
    private let answer: FakeAnswer
    private(set) var sent: [Data] = []
    private(set) var answerTimeouts: [Duration] = []

    init(_ answer: FakeAnswer) {
        self.answer = answer
    }

    func exchange(_ line: Data, to socket: String, connectTimeout: Duration, answerTimeout: Duration)
        throws(TransportError) -> Data
    {
        sent.append(line)
        answerTimeouts.append(answerTimeout)
        switch answer {
        case .unreachable: throw .unreachable(socket)
        case .timeout: throw .unreachable("timeout")
        case .closed: return Data()
        case .garbage: return Data("nope\n".utf8)
        case .response(let response): return (try? IPCCodec.encode(response)) ?? Data()
        }
    }

    var payload: [String: Any] {
        guard let line = sent.first, let request = try? IPCCodec.decodeRequest(line.dropLast()) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: request.payload)) as? [String: Any] ?? [:]
    }
}

@Suite("smalti guard")
struct GuardCommandTests {
    static let environment = [
        "SMALTI_SOCKET": "/tmp/s.sock", "SMALTI_PANE_ID": "8D8AC610-566D-4EF0-9C22-186B2A5ED793", "HOME": "/Users/u",
    ]

    static func bash(_ command: String, cwd: String = "/p") -> String {
        let object: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": command], "cwd": cwd]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
    }

    static func read(_ path: String) -> String {
        #"{"tool_name":"Read","tool_input":{"file_path":"\#(path)"},"cwd":"/p"}"#
    }

    private func run(
        _ input: String, _ answer: FakeAnswer, environment: [String: String] = environment
    ) -> (output: String, transport: FakeGuardTransport) {
        let transport = FakeGuardTransport(answer)
        let output = GuardCommand.run(
            Invocation(arguments: ["guard", "PreToolUse"], environment: environment, input: { Data(input.utf8) }),
            transport: transport, deadline: .seconds(630))
        return (output, transport)
    }

    static func denial(_ reason: String) -> String {
        let object: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason,
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static let secretCases = [
        read("/p/.env"), read("/p/config/.env.production"), read("/Users/u/.ssh/id_rsa"), read("/p/tls.key"),
        #"{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":"/p/.env.local"},"cwd":"/p"}"#,
        #"{"tool_name":"Grep","tool_input":{"pattern":"KEY","glob":".env*"},"cwd":"/p"}"#,
        #"{"tool_name":"Edit","tool_input":{"file_path":"/p/.env","old_string":"a","new_string":"b"},"cwd":"/p"}"#,
        #"{"tool_name":"Write","tool_input":{"file_path":"/p/.env","content":"x"},"cwd":"/p"}"#,
        bash("cat .env"), bash("less .env.local"), bash("head -n 5 .env.production"), bash("tail .env"),
        bash("grep KEY .env"), bash("sed -n 1p .env"), bash("awk '{print}' .env"), bash("source .env"),
        bash(". ./.env"), bash("cp .env /tmp/x"), bash("tar czf x.tgz .env"), bash("base64 < .env"),
        bash("xxd .env"), bash("strings .env"), bash("echo $(cat .env)"), bash("cat .e\"n\"v"),
        bash("cat ~/.ssh/id_rsa"), bash("cat $HOME/.aws/credentials"), bash("cat ${HOME}/.netrc"),
        bash("git show HEAD:.env"), bash("python3 -c \"print(open('.env').read())\""),
        bash("node -e \"require('fs').readFileSync('.env')\""), bash("bash -c 'cat .env'"),
        bash("security find-generic-password -s x -w"), bash("cat .ssh/config", cwd: "/Users/u"),
    ]

    @Test(arguments: secretCases)
    func secretDeniedWithoutApp(input: String) {
        #expect(run(input, .unreachable).output.contains(#""permissionDecision":"deny""#))
    }

    @Test(arguments: [
        bash("cat .env.example"), bash("cat ~/.ssh/id_rsa.pub"), bash("ls -la .env"), bash("echo \"rellena .env\""),
        bash("cat README.md"), read("/p/src/a.ts"),
    ])
    func innocentAllowedWithoutApp(input: String) {
        #expect(run(input, .unreachable).output == "")
    }

    @Test func secretDenialIsExactJSON() {
        #expect(
            run(Self.read("/p/.env"), .unreachable).output
                == Self.denial(GuardTexts.spanish.secretReason(["path": "/p/.env"])))
    }

    @Test(arguments: [FakeAnswer.unreachable, .timeout, .closed, .garbage])
    func askDeniedWhenAppDoesNotAnswer(answer: FakeAnswer) {
        #expect(run(Self.bash("terraform destroy"), answer).output == Self.denial(GuardTexts.spanish.unreachable))
    }

    @Test func askDeniedWhenAppDoesNotKnowGuards() {
        let old = IPCResponse(ok: false, error: "unsupported request v1 guard")

        #expect(
            run(Self.bash("terraform destroy"), .response(old)).output == Self.denial(GuardTexts.spanish.unreachable))
    }

    @Test func askDeniedWhenAnswerHasNoDecision() {
        let output = run(Self.bash("terraform destroy"), .response(IPCResponse(ok: true, error: nil))).output

        #expect(output == Self.denial(GuardTexts.spanish.unreachable))
    }

    @Test func appAllowIsSilent() {
        let allow = IPCResponse(ok: true, error: nil, decision: .allow, reason: nil)

        #expect(run(Self.bash("terraform destroy"), .response(allow)).output == "")
    }

    @Test func appDenyCarriesReason() {
        let deny = IPCResponse(ok: true, error: nil, decision: .deny, reason: "rechazado")

        #expect(run(Self.bash("terraform destroy"), .response(deny)).output == Self.denial("rechazado"))
    }

    @Test func secretStaysDeniedEvenIfAppAllows() {
        let allow = IPCResponse(ok: true, error: nil, decision: .allow, reason: nil)

        #expect(run(Self.bash("cat .env"), .response(allow)).output.contains(#""permissionDecision":"deny""#))
    }

    @Test func askWaitsUpToTheDeadline() {
        let allow = IPCResponse(ok: true, error: nil, decision: .allow, reason: nil)

        let transport = run(Self.bash("terraform destroy"), .response(allow)).transport

        #expect(transport.answerTimeouts == [.seconds(630)])
    }

    @Test func requestCarriesToolUseAndVerdict() throws {
        let transport = run(Self.bash("terraform destroy"), .unreachable).transport
        let request = try IPCCodec.decodeRequest(try #require(transport.sent.first).dropLast())

        #expect(request.kind == IPCRequest.guardKind)
        #expect(request.pane == "8D8AC610-566D-4EF0-9C22-186B2A5ED793")
        #expect((transport.payload["tool_input"] as? [String: String])?["command"] == "terraform destroy")
        #expect(transport.payload["local_verdict"] as? String == "ask")
        #expect(transport.payload["cwd"] as? String == "/p")
    }

    @Test func environmentURLReducedToHost() throws {
        var environment = Self.environment
        environment["DATABASE_URL"] = "postgres://admin:p4ss@db.x.supabase.co:5432/postgres"
        environment["DIRECT_URL"] = "postgres://u:p4ss@localhost/x"

        let transport = run(Self.bash("npm run db:push"), .unreachable, environment: environment).transport
        let line = String(decoding: try #require(transport.sent.first), as: UTF8.self)

        #expect(!line.contains("p4ss"))
        #expect(transport.payload["env_database_hosts"] as? [String] == ["db.x.supabase.co", "localhost"])
    }

    @Test func outsideSmaltiDoesNothingForInnocentButDeniesSecrets() {
        let outside = ["HOME": "/Users/u"]

        #expect(run(Self.bash("git status"), .unreachable, environment: outside).output == "")
        #expect(run(Self.bash("cat .env"), .unreachable, environment: outside).output.contains("deny"))
        #expect(run(Self.bash("terraform destroy"), .unreachable, environment: outside).output.contains("deny"))
        #expect(run(Self.bash("git status"), .unreachable, environment: outside).transport.sent.isEmpty)
    }

    /// Review 1: a hook input Smalti cannot read is not let through.
    @Test func unreadableInputIsDenied() {
        #expect(run("not json", .unreachable).output == Self.denial(GuardTexts.spanish.unreadableInput))
        #expect(run(#"{"cwd":"/p"}"#, .unreachable).output == Self.denial(GuardTexts.spanish.unreadableInput))
    }

    @Test func eventPreToolUseDeniesUnreadableInput() {
        #expect(
            EventCommand.preToolUseOutput(Data("{".utf8), environment: Self.environment)
                == Self.denial(GuardTexts.spanish.unreadableInput))
    }

    /// Review 1 (C1): the app must know the command was cut, so it asks instead of judging the cut text.
    @Test func oversizedCommandIsSentAsTruncated() {
        let long = Self.bash("echo " + String(repeating: "a", count: 70_000) + "; terraform destroy")
        let allow = IPCResponse(ok: true, error: nil, decision: .allow, reason: nil)

        let transport = run(long, .response(allow)).transport

        #expect(transport.payload["truncated"] as? Bool == true)
    }

    @Test func normalCommandIsNotTruncated() {
        #expect(run(Self.bash("terraform destroy"), .unreachable).transport.payload["truncated"] == nil)
    }

    @Test func oversizedCommandAsks() {
        let long = Self.bash("echo " + String(repeating: "a", count: 70_000))

        #expect(run(long, .unreachable).output == Self.denial(GuardTexts.spanish.unreachable))
    }

    @Test func eventPreToolUseDeniesAskAsOutdated() {
        let output = EventCommand.preToolUseOutput(
            Data(Self.bash("terraform destroy").utf8), environment: Self.environment)

        #expect(output == Self.denial(GuardTexts.spanish.outdatedIntegration))
    }

    @Test func eventPreToolUseDeniesSecrets() {
        let output = EventCommand.preToolUseOutput(Data(Self.read("/p/.env").utf8), environment: Self.environment)

        #expect(output == Self.denial(GuardTexts.spanish.secretReason(["path": "/p/.env"])))
    }

    @Test func eventPreToolUseLetsInnocentPass() {
        #expect(EventCommand.preToolUseOutput(Data(Self.bash("git status").utf8), environment: Self.environment) == "")
    }

    @Test func versionIsTwo() {
        #expect(EventCommand.version == "0.2.0")
    }
}
