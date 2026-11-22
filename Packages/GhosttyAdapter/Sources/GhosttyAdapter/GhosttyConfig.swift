import Foundation
import GhosttyKit
import SmaltiCore

/// Owns a finalized libghostty config built only from Smalti's generated file, never from ~/.config/ghostty.
public final class GhosttyConfig {
    let handle: ghostty_config_t

    private init(handle: ghostty_config_t) {
        self.handle = handle
    }

    deinit {
        ghostty_config_free(handle)
    }

    @MainActor
    public static func load(text: String, writingTo url: URL) throws(TerminalEngineError) -> GhosttyConfig {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw .configurationInvalid(diagnostics: ["cannot write \(url.path(percentEncoded: false)): \(error)"])
        }
        guard let handle = ghostty_config_new() else {
            throw .engineStartFailed(reason: "ghostty_config_new returned null")
        }
        let config = GhosttyConfig(handle: handle)
        ghostty_config_load_file(handle, url.path(percentEncoded: false))
        ghostty_config_finalize(handle)
        let diagnostics = config.diagnostics()
        guard diagnostics.isEmpty else { throw .configurationInvalid(diagnostics: diagnostics) }
        return config
    }

    private func diagnostics() -> [String] {
        (0..<ghostty_config_diagnostics_count(handle)).compactMap { index in
            ghostty_config_get_diagnostic(handle, index).message.map { String(cString: $0) }
        }
    }
}
