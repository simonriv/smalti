import Foundation
import SmaltiCore

/// Installs Smalti's Claude Code plugin as a local marketplace. The plugin is copied to a stable place shared by both
/// builds (`~/Library/Application Support/Smalti/claude-plugin/`), because its hooks find their Smalti through the
/// pane's `SMALTI_CLI`: installing from "Smalti Dev" does not break the daily build.
@MainActor
public final class ClaudePluginInstaller: HarnessIntegration {
    static let marketplace = "smalti"
    static let plugin = "smalti@smalti"
    /// What a shell answers when the command does not exist.
    static let commandNotFound: Int32 = 127

    private let pluginSource: URL
    private let installDirectory: URL
    private let runner: any CommandRunner
    /// `claude`, or what the UI tests run instead (`-SmaltiClaudeCommand`): `/bin/sh <script>`, because a script
    /// written by the sandboxed test runner is quarantined and cannot be executed directly.
    private let command: [String]

    public init(
        pluginSource: URL, installDirectory: URL, runner: any CommandRunner, command: [String] = ["claude"]
    ) {
        self.pluginSource = pluginSource
        self.installDirectory = installDirectory
        self.runner = runner
        self.command = command
    }

    public func install() async throws(IntegrationError) {
        try copyPlugin()
        // A marketplace added before (maybe by the other build) is replaced, so its path is this copy.
        _ = await runner.run(command + ["plugin", "marketplace", "remove", Self.marketplace])
        try await claude(["plugin", "marketplace", "add", installDirectory.path(percentEncoded: false)])
        try await claude(["plugin", "install", Self.plugin])
    }

    /// Both steps run even if the first fails (the plugin may already be gone); the first failure is reported.
    public func uninstall() async throws(IntegrationError) {
        var failure: IntegrationError?
        for step in [["plugin", "uninstall", Self.plugin], ["plugin", "marketplace", "remove", Self.marketplace]] {
            do {
                try await claude(step)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
    }

    /// A missing `claude`, a shell that cannot start or a failing list leave the state unknown (spec F5.6).
    public var installState: IntegrationState {
        get async {
            let result = await runner.run(command + ["plugin", "list"])
            guard result.status == 0 else { return .unknown }
            return result.output.contains(Self.plugin) ? .installed : .notInstalled
        }
    }

    private func claude(_ arguments: [String]) async throws(IntegrationError) {
        let result = await runner.run(command + arguments)
        if result.status == CommandResult.launchFailed {
            throw .commandFailed(command: runner.launcher, output: "the shell could not start")
        }
        if result.status == Self.commandNotFound { throw .harnessMissing(binary: "claude") }
        guard result.status == 0 else {
            throw .commandFailed(command: (["claude"] + arguments).joined(separator: " "), output: result.output)
        }
    }

    private func copyPlugin() throws(IntegrationError) {
        let files = FileManager.default
        do {
            try files.createDirectory(
                at: installDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: installDirectory.path(percentEncoded: false)) {
                try files.removeItem(at: installDirectory)
            }
            try files.copyItem(at: pluginSource, to: installDirectory)
        } catch {
            throw .commandFailed(command: "copy \(pluginSource.lastPathComponent)", output: String(describing: error))
        }
    }
}
