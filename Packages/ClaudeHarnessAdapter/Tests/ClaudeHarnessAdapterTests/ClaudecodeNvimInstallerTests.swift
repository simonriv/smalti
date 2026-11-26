import ClaudeHarnessAdapter
import Foundation
import SmaltiCore
import Testing

/// The installer only ever touches a temporary XDG_CONFIG_HOME here, never the user's `~/.config/nvim`.
@MainActor
@Suite("claudecode.nvim installer")
struct ClaudecodeNvimInstallerTests {
    private let xdg = FileManager.default.temporaryDirectory.appending(path: "nvim-xdg-\(UUID())")
    private var nvim: URL { xdg.appending(path: "nvim") }
    private var installed: URL { nvim.appending(path: "lua/plugins/smalti-claudecode.lua") }

    private func nvChadStarter() throws {
        try FileManager.default.createDirectory(
            at: nvim.appending(path: "lua/plugins"), withIntermediateDirectories: true)
        try #"require("lazy").setup({ { "NvChad/NvChad", import = "nvchad.plugins" }, { import = "plugins" } })"#
            .write(to: nvim.appending(path: "init.lua"), atomically: true, encoding: .utf8)
        try "return {}\n".write(to: nvim.appending(path: "lua/plugins/init.lua"), atomically: true, encoding: .utf8)
    }

    private func snapshot() throws -> [String: Data] {
        let files =
            FileManager.default.enumerator(at: nvim, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return Dictionary(
            uniqueKeysWithValues: try files.filter { !$0.hasDirectoryPath }.map {
                (
                    $0.resolvingSymlinksInPath().path.replacingOccurrences(
                        of: nvim.resolvingSymlinksInPath().path, with: ""), try Data(contentsOf: $0)
                )
            })
    }

    @Test func installsOwnFileOnly() async throws {
        try nvChadStarter()
        let before = try snapshot()
        let installer = ClaudecodeNvimInstaller(configHome: nvim)

        #expect(await installer.installState == .notInstalled)
        try await installer.install()

        let after = try snapshot()
        #expect(Set(after.keys).subtracting(before.keys) == ["/lua/plugins/smalti-claudecode.lua"])
        #expect(before.allSatisfy { after[$0.key] == $0.value })
        let text = try String(contentsOf: installed, encoding: .utf8)
        #expect(text.hasPrefix(ClaudecodeNvimInstaller.marker))
        #expect(text.contains(#""coder/claudecode.nvim""#))
        #expect(text.contains(#"tag = "v0.4.0""#))
        #expect(text.contains(#"provider = "none""#))
        #expect(await installer.installState == .installed)
    }

    /// Restore asks right away, before the palette's first background check has answered.
    @Test func isInstalledAnswersWithoutWaiting() async throws {
        try nvChadStarter()
        let installer = ClaudecodeNvimInstaller(configHome: nvim)
        #expect(!installer.isInstalled)

        try await installer.install()

        #expect(installer.isInstalled)
    }

    @Test func uninstallRemovesOnlyItsFile() async throws {
        try nvChadStarter()
        let installer = ClaudecodeNvimInstaller(configHome: nvim)
        try await installer.install()

        try await installer.uninstall()

        #expect(!FileManager.default.fileExists(atPath: installed.path))
        #expect(FileManager.default.fileExists(atPath: nvim.appending(path: "lua/plugins/init.lua").path))
        #expect(await installer.installState == .notInstalled)
    }

    @Test func uninstallKeepsUnmarkedFile() async throws {
        try nvChadStarter()
        try "return { 'mine' }\n".write(to: installed, atomically: true, encoding: .utf8)
        let installer = ClaudecodeNvimInstaller(configHome: nvim)

        #expect(await installer.installState == .unknown)
        await #expect(throws: IntegrationError.self) { try await installer.uninstall() }
        await #expect(throws: IntegrationError.self) { try await installer.install() }
        #expect(try String(contentsOf: installed, encoding: .utf8) == "return { 'mine' }\n")
    }

    @Test func nonNvChadConfigIsUnknown() async throws {
        try FileManager.default.createDirectory(at: nvim, withIntermediateDirectories: true)
        try "vim.opt.number = true\n".write(to: nvim.appending(path: "init.lua"), atomically: true, encoding: .utf8)

        #expect(await ClaudecodeNvimInstaller(configHome: nvim).installState == .unknown)
        #expect(await ClaudecodeNvimInstaller(configHome: xdg.appending(path: "missing")).installState == .unknown)
    }

    nonisolated static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/nvim-fixtures")

    @Test(
        .enabled(
            if: FileManager.default.fileExists(atPath: fixtures.appending(path: "init.lua").path),
            "run scripts/harnesses/prepare-nvim-fixtures.sh"))
    func headlessNvimLoadsInstalledPlugin() async throws {
        try nvChadStarter()
        try await ClaudecodeNvimInstaller(configHome: nvim).install()
        let process = Process()
        process.executableURL = URL(filePath: "/opt/homebrew/bin/nvim")
        process.arguments = [
            "--headless", "-u", Self.fixtures.appending(path: "init.lua").path,
            "+lua assert(require('claudecode')); io.stdout:write('LOADED')", "+qa!",
        ]
        process.environment = [
            "HOME": xdg.path, "XDG_CONFIG_HOME": xdg.path, "XDG_DATA_HOME": xdg.appending(path: "data").path,
            "XDG_STATE_HOME": xdg.appending(path: "state").path, "XDG_CACHE_HOME": xdg.appending(path: "cache").path,
            "CLAUDE_CONFIG_DIR": xdg.appending(path: "claude").path, "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(text)")
        #expect(text.contains("LOADED"), "\(text)")
    }
}

/// F7.7: any lazy.nvim config that imports `plugins` (NvChad, the LazyVim starter, your own), not just NvChad.
@MainActor
@Suite("claudecode.nvim with lazy.nvim configs")
struct LazyNvimDetectionTests {
    private let nvim = FileManager.default.temporaryDirectory.appending(path: "nvim-lazy-\(UUID())/nvim")

    private func write(_ text: String, to relative: String) throws {
        let file = nvim.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test func lazyVimStarterLayoutIsDetected() async throws {
        defer { try? FileManager.default.removeItem(at: nvim.deletingLastPathComponent()) }
        try write(#"require("config.lazy")"#, to: "init.lua")
        try write(
            #"require("lazy").setup({ spec = { { "LazyVim/LazyVim", import = "lazyvim.plugins" }, { import = "plugins" } } })"#,
            to: "lua/config/lazy.lua")
        try write("return {}\n", to: "lua/plugins/example.lua")

        let installer = ClaudecodeNvimInstaller(configHome: nvim)

        #expect(await installer.installState == .notInstalled)
        try await installer.install()
        #expect(FileManager.default.fileExists(atPath: nvim.appending(path: "lua/plugins/smalti-claudecode.lua").path))
    }

    @Test func singleQuotesCount() async throws {
        defer { try? FileManager.default.removeItem(at: nvim.deletingLastPathComponent()) }
        try write("require('lazy').setup({ { import = 'plugins' } })", to: "init.lua")
        try write("return {}\n", to: "lua/plugins/init.lua")

        #expect(await ClaudecodeNvimInstaller(configHome: nvim).installState == .notInstalled)
    }

    @Test func kickstartWithoutPluginsFolderIsUnknown() async throws {
        defer { try? FileManager.default.removeItem(at: nvim.deletingLastPathComponent()) }
        try write("require('lazy').setup({ 'tpope/vim-sleuth' })", to: "init.lua")

        #expect(await ClaudecodeNvimInstaller(configHome: nvim).installState == .unknown)
    }

    /// The real LazyVim starter, cloned into a temporary folder; skipped without network or git.
    @Test func realLazyVimStarterIsDetected() async throws {
        let base = nvim.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: base) }
        let git = Process()
        git.executableURL = URL(filePath: "/usr/bin/git")
        git.arguments = ["clone", "--depth", "1", "--quiet", "https://github.com/LazyVim/starter", nvim.path]
        git.environment = ["GIT_TERMINAL_PROMPT": "0", "PATH": "/usr/bin:/bin"]
        try git.run()
        git.waitUntilExit()
        try #require(git.terminationStatus == 0, "git clone of LazyVim/starter failed (no network?)")

        #expect(await ClaudecodeNvimInstaller(configHome: nvim).installState == .notInstalled)
    }
}
