import SmaltiCore
import Testing

/// Spec F5, the channel's new messages: `context` from zsh, `prompt` and `promptstyle` from Smalti.
@Suite("InputProtocol · F5")
struct InputProtocolF5Tests {
    private let rendered = RenderedPrompt(
        immediate: "%F{#7aa2f7}${_smalti_dir}%f\n${_smalti_sym} ", full: "%F{#7aa2f7}${_smalti_p_1}%f",
        values: ["_smalti_sym": "›", "_smalti_p_1": "solen"], directoryLabel: "solen")

    @Test func contextRoundTrips() throws {
        let context = ShellContext(
            pwd: "/Users/simon/dev/solen", exit: 1, durationMilliseconds: 4249, awsProfile: "prod",
            kubeconfig: "/Users/simon/.kube/config",
            runtimePaths: [.node: "/opt/homebrew/bin/node", .go: "/usr/local/go/bin/go"])
        let packet = ShellPacket(.context(seq: 7, context), directory: context.pwd)

        let line = try #require(InputProtocol.encode(packet))

        #expect(try InputProtocol.decode(line) == packet)
    }

    @Test func contextWireFormat() {
        let context = ShellContext(
            pwd: "/tmp", exit: 0, durationMilliseconds: 12, awsProfile: nil, kubeconfig: nil,
            runtimePaths: [.node: "/bin/node", .bun: "/bin/bun"])

        let line = InputProtocol.encode(ShellPacket(.context(seq: 3, context), directory: "/tmp"))

        #expect(line == "context\t3\t/tmp\t0\t12\t\t\tbun=/bin/bun;node=/bin/node")
    }

    @Test func contextWithoutOptionalsDecodesNil() throws {
        let packet = try InputProtocol.decode("context\t3\t/tmp\t0\t12\t\t\t")

        guard case .context(3, let context) = packet.message else {
            Issue.record("not a context: \(packet.message)")
            return
        }
        #expect(context.awsProfile == nil)
        #expect(context.kubeconfig == nil)
        #expect(context.runtimePaths.isEmpty)
        #expect(packet.directory == "/tmp")
    }

    @Test func unknownRuntimeIsIgnored() throws {
        let packet = try InputProtocol.decode("context\t1\t/tmp\t0\t0\t\t\tdeno=/bin/deno;go=/bin/go")

        guard case .context(_, let context) = packet.message else {
            Issue.record("not a context")
            return
        }
        #expect(context.runtimePaths == [.go: "/bin/go"])
    }

    @Test func promptWireFormatSortsValues() {
        let line = InputProtocol.encode(.prompt(seq: 9, rendered))

        #expect(
            line
                == "prompt\t9\tsolen\t%F{#7aa2f7}${_smalti_dir}%f\\n${_smalti_sym} \t%F{#7aa2f7}${_smalti_p_1}%f\t"
                + "_smalti_p_1=solen\u{1f}_smalti_sym=›")
    }

    @Test func promptStyleCarriesImmediateGhostAndValues() {
        let ghost = RGBAColor(red: 0x8b, green: 0x91, blue: 0x9c, alpha: 1)

        let line = InputProtocol.encode(.promptStyle(rendered, ghost: ghost))

        #expect(
            line
                == "promptstyle\t%F{#7aa2f7}${_smalti_dir}%f\\n${_smalti_sym} \t#8b919c\t_smalti_p_1=solen\u{1f}_smalti_sym=›"
        )
    }

    @Test func fieldsWithTabAreEscaped() throws {
        let context = ShellContext(
            pwd: "/tmp/a\tb", exit: 0, durationMilliseconds: 0, awsProfile: "x\ty", kubeconfig: nil, runtimePaths: [:])
        let packet = ShellPacket(.context(seq: 1, context), directory: context.pwd)

        let line = try #require(InputProtocol.encode(packet))

        #expect(try InputProtocol.decode(line) == packet)
    }
}
