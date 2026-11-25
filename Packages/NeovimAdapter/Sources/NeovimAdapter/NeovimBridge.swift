import Foundation
import SmaltiCore

/// `EditorBridge` over Neovim's msgpack-RPC socket. The file and line go to a fixed Lua chunk as arguments, never as
/// typed text or an Ex command, so no file name can run anything (spec F6, review focus 3).
@MainActor
public final class NeovimBridge: EditorBridge {
    static let openTimeout: TimeInterval = 1
    static let currentTimeout: TimeInterval = 0.2

    static let openChunk = """
        local file, line, column = ...
        local buffer = vim.fn.bufadd(file)
        vim.bo[buffer].buflisted = true
        vim.fn.bufload(buffer)
        vim.api.nvim_set_current_buf(buffer)
        if line ~= vim.NIL and line ~= nil then
          local last = vim.api.nvim_buf_line_count(buffer)
          local col = (column ~= vim.NIL and column ~= nil) and column - 1 or 0
          vim.api.nvim_win_set_cursor(0, { math.min(line, last), math.max(col, 0) })
        end
        """
    static let currentChunk = "return { vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1] }"

    public init() {}

    public func open(_ target: EditorTarget, socket: String) async throws(EditorError) {
        let params: [MsgPackValue] = [
            .string(Self.openChunk),
            .array([
                .string(target.path), target.line.map { .int(Int64($0)) } ?? .nil,
                target.column.map { .int(Int64($0)) } ?? .nil,
            ]),
        ]
        _ = try await Self.call(socket, "nvim_exec_lua", params, timeout: Self.openTimeout)
    }

    public func current(socket: String) async -> EditorPosition? {
        let result = try? await Self.call(
            socket, "nvim_exec_lua", [.string(Self.currentChunk), .array([])], timeout: Self.currentTimeout)
        guard case .array(let parts) = result, parts.count == 2, case .string(let file) = parts[0], !file.isEmpty,
            case .int(let line) = parts[1]
        else { return nil }
        return EditorPosition(file: file, line: Int(line))
    }

    /// The blocking socket work runs off the main thread.
    private static func call(_ socket: String, _ method: String, _ params: [MsgPackValue], timeout: TimeInterval)
        async throws(EditorError) -> MsgPackValue
    {
        let result = await Task.detached {
            Result { () throws(EditorError) -> MsgPackValue in
                try NeovimRPC.call(socket: socket, method: method, params: params, timeout: timeout)
            }
        }.value
        return try result.get()
    }
}
