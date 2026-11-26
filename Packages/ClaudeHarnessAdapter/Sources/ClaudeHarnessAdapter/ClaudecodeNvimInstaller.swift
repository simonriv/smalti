import Foundation
import SmaltiCore

/// Installs claudecode.nvim in the user's lazy.nvim config (NvChad, the LazyVim starter or their own) as one file of its own, `lua/plugins/smalti-claudecode.lua`,
/// marked as Smalti's: lazy.nvim installs the plugin on Neovim's next start, and uninstalling removes only that file
/// (spec F6). Claude runs in its Smalti pane, so the plugin opens no terminal of its own.
@MainActor
public final class ClaudecodeNvimInstaller: HarnessIntegration {
    public static let marker = "-- Instalado por Smalti"
    static let relativePath = "lua/plugins/smalti-claudecode.lua"
    static let contents = """
        \(marker): claudecode.nvim para aprobar los diffs de Claude Code (⌘K › Desinstalar claudecode.nvim lo quita).
        return {
          {
            "coder/claudecode.nvim",
            tag = "v0.4.0",
            lazy = false,
            opts = { terminal = { provider = "none" } },
          },
        }

        """

    private let configHome: URL

    /// `configHome` is Neovim's config folder (`$XDG_CONFIG_HOME/nvim`), resolved by the composition root.
    public init(configHome: URL) {
        self.configHome = configHome
    }

    private var file: URL { configHome.appending(path: Self.relativePath) }

    public var installState: IntegrationState {
        get async { currentState }
    }

    /// Only file checks, so restoring can ask without waiting for ⌘K's background check (`--ide`, spec F6).
    public var isInstalled: Bool { currentState == .installed }

    private var currentState: IntegrationState {
        guard importsPluginsFolder else { return .unknown }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: file.path) ? .unknown : .notInstalled
        }
        return text.hasPrefix(Self.marker) ? .installed : .unknown
    }

    public func install() async throws(IntegrationError) {
        guard await installState != .unknown else { throw refusal("install") }
        do {
            try Self.contents.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            throw .commandFailed(command: "write \(file.path)", output: String(describing: error))
        }
    }

    public func uninstall() async throws(IntegrationError) {
        guard await installState == .installed else { throw refusal("uninstall") }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            throw .commandFailed(command: "remove \(file.path)", output: String(describing: error))
        }
    }

    /// F7.7: lazy.nvim configs that keep plugins in `lua/plugins/` and import them, from `init.lua` (NvChad) or
    /// `lua/config/lazy.lua` (the LazyVim starter), with either quote. Others are left alone and documented.
    private var importsPluginsFolder: Bool {
        let plugins = configHome.appending(path: "lua/plugins")
        var isDirectory: ObjCBool = false
        let hasPlugins =
            FileManager.default.fileExists(atPath: plugins.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        return hasPlugins
            && Self.setupFiles.contains { relative in
                let text = (try? String(contentsOf: configHome.appending(path: relative), encoding: .utf8)) ?? ""
                return Self.importLines.contains { text.contains($0) }
            }
    }

    private static let setupFiles = ["init.lua", "lua/config/lazy.lua"]
    private static let importLines = [#"import = "plugins""#, "import = 'plugins'"]

    private func refusal(_ action: String) -> IntegrationError {
        .commandFailed(
            command: "\(action) claudecode.nvim",
            output: "\(file.path) is not Smalti's, or the config does not import lua/plugins with lazy.nvim")
    }
}
