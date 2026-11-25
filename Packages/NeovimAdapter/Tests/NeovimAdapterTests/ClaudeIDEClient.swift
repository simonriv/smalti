import Foundation

/// Speaks Claude Code's side of the IDE protocol (MCP over a WebSocket) to claudecode.nvim, so the diff criterion
/// (spec F6, C3) runs without Claude: it reads the lock file Neovim wrote under `CLAUDE_CONFIG_DIR/ide`, connects
/// with its token and calls tools as Claude does.
final class ClaudeIDEClient: @unchecked Sendable {
    struct Lock: Decodable {
        let authToken: String
    }

    private let task: URLSessionWebSocketTask
    private var nextID = 1

    init(claudeConfig: URL, timeout: TimeInterval = 5) async throws {
        let folder = claudeConfig.appending(path: "ide")
        var lockFile: URL?
        let deadline = Date().addingTimeInterval(timeout)
        while lockFile == nil, Date() < deadline {
            lockFile = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .first { $0.pathExtension == "lock" }
            if lockFile == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        let file = try lockFileOrThrow(lockFile)
        let port = file.deletingPathExtension().lastPathComponent
        let lock = try JSONDecoder().decode(Lock.self, from: Data(contentsOf: file))
        var request = URLRequest(url: try urlOrThrow(URL(string: "ws://127.0.0.1:\(port)")))
        request.setValue(lock.authToken, forHTTPHeaderField: "x-claude-code-ide-authorization")
        task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        _ = try await call(
            "initialize",
            [
                "protocolVersion": "2025-06-18", "capabilities": [String: Any](),
                "clientInfo": ["name": "smalti-tests", "version": "1"],
            ])
    }

    deinit { close() }

    func close() { task.cancel(with: .goingAway, reason: nil) }

    /// `tools/call` and the texts of its result (`["FILE_SAVED", contents]` or `["DIFF_REJECTED", tab]`).
    func callTool(_ name: String, _ arguments: [String: Any]) async throws -> [String] {
        let result = try await call("tools/call", ["name": name, "arguments": arguments])
        let content = (result["content"] as? [[String: Any]]) ?? []
        return content.compactMap { $0["text"] as? String }
    }

    private func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: message)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
        while true {
            let received = try await task.receive()
            guard case .string(let text) = received,
                let reply = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                reply["id"] as? Int == id
            else { continue }
            if let error = reply["error"] { throw CocoaError(.featureUnsupported, userInfo: ["error": "\(error)"]) }
            return reply["result"] as? [String: Any] ?? [:]
        }
    }
}

private func lockFileOrThrow(_ file: URL?) throws -> URL {
    guard let file else { throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "no IDE lock file"]) }
    return file
}

private func urlOrThrow(_ url: URL?) throws -> URL {
    guard let url else { throw CocoaError(.fileReadInvalidFileName) }
    return url
}
