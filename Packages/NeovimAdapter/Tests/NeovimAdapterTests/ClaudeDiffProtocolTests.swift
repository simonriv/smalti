import Foundation
import SmaltiCore
import Testing

@testable import NeovimAdapter

/// C3 (amended): a diff sent with Claude's protocol is accepted with `:w` and rejected with `:q`. Neovim runs with
/// `--clean`, its own socket, claudecode.nvim from `build/nvim-fixtures` (prepare-nvim-fixtures.sh) and a temporary
/// `CLAUDE_CONFIG_DIR`.
enum ClaudecodeFixture {
    static let plugin = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "build/nvim-fixtures/plugins/claudecode.nvim")
    static var canRun: Bool {
        TestNeovim.isAvailable && FileManager.default.fileExists(atPath: plugin.appending(path: "lua").path)
    }
}

@Suite(
    "Claude diff protocol", .serialized,
    .enabled(if: ClaudecodeFixture.canRun, "nvim or build/nvim-fixtures (prepare-nvim-fixtures.sh) is missing"))
struct ClaudeDiffProtocolTests {
    private func neovim() throws -> (TestNeovim, URL) {
        let claude = URL(filePath: "/private/tmp/smalti-claude-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let nvim = try TestNeovim(
            arguments: [
                "--cmd", "set rtp^=\(ClaudecodeFixture.plugin.path)",
                "+lua require('claudecode').setup({ terminal = { provider = 'none' }, log_level = 'error' })",
            ],
            environment: ["CLAUDE_CONFIG_DIR": claude.path])
        return (nvim, claude)
    }

    private func file(in nvim: TestNeovim) throws -> URL {
        let file = nvim.folder.appending(path: "greet.ts")
        try "function greet() {\n  return 'hola'\n}\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Waits for the proposed buffer, focuses its window and runs `command` there, as the user would.
    private func answer(_ command: String, in nvim: TestNeovim) async throws {
        let chunk = """
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
              if name:sub(-6) == " (New)" or name:sub(-11) == " (proposed)" then
                vim.api.nvim_set_current_win(win)
                vim.cmd(...)
                return true
              end
            end
            return false
            """
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let done = try? NeovimRPC.call(
                socket: nvim.socket, method: "nvim_exec_lua", params: [.string(chunk), .array([.string(command)])],
                timeout: 1)
            if done == .bool(true) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("the proposed buffer never opened")
    }

    /// The diff's answer, or a failure after 15 s that closes the connection so the test never hangs.
    private func openDiff(_ client: ClaudeIDEClient, _ file: URL) async throws -> [String] {
        try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask { try await self.sendDiff(client, file) }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                client.close()
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private func sendDiff(_ client: ClaudeIDEClient, _ file: URL) async throws -> [String] {
        try await client.callTool(
            "openDiff",
            [
                "old_file_path": file.path, "new_file_path": file.path,
                "new_file_contents": "function greet(name) {\n  return `hola ${name}`\n}\n", "tab_name": "greet.ts ⧉",
            ])
    }

    @Test func writeAcceptsDiff() async throws {
        let (nvim, claude) = try neovim()
        defer { try? FileManager.default.removeItem(at: claude) }
        let file = try file(in: nvim)
        let client = try await ClaudeIDEClient(claudeConfig: claude)

        async let result = openDiff(client, file)
        try await answer("w", in: nvim)

        let texts = try await result
        #expect(texts.first == "FILE_SAVED")
        #expect(texts.dropFirst().first?.contains("hola ${name}") == true)
    }

    @Test func quitRejectsDiff() async throws {
        let (nvim, claude) = try neovim()
        defer { try? FileManager.default.removeItem(at: claude) }
        let file = try file(in: nvim)
        let client = try await ClaudeIDEClient(claudeConfig: claude)

        async let result = openDiff(client, file)
        try await answer("q", in: nvim)

        #expect(try await result.first == "DIFF_REJECTED")
        #expect(try String(contentsOf: file, encoding: .utf8).contains("return 'hola'"))
    }
}
