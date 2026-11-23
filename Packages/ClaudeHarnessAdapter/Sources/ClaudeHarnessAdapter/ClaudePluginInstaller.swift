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

    public init(pluginSource: URL, installDirectory: URL, runner: any CommandRunner) {
        self.pluginSource = pluginSource
        self.installDirectory = installDirectory
        self.runner = runner
    }

    public func install() async throws(IntegrationError) {
        try copyPlugin()
        // A marketplace added before (maybe by the other build) is replaced, so its path is this copy.
        _ = await runner.run(["claude", "plugin", "marketplace", "remove", Self.marketplace])
        try await claude(["plugin", "marketplace", "add", installDirectory.path(percentEncoded: false)])
        try await claude(["plugin", "install", Self.plugin])
    }

    public func uninstall() async throws(IntegrationError) {
        try await claude(["plugin", "uninstall", Self.plugin])
        try await claude(["plugin", "marketplace", "remove", Self.marketplace])
    }

    public var isInstalled: Bool {
        get async {
            let result = await runner.run(["claude", "plugin", "list"])
            return result.status == 0 && result.output.contains(Self.plugin)
        }
    }

    private func claude(_ arguments: [String]) async throws(IntegrationError) {
        let result = await runner.run(["claude"] + arguments)
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
