import AppKit
import OSLog

/// Opens a file the way the user expects; `-SmaltiOpenLog <file>` writes the path there instead (UI tests).
@MainActor
enum URLOpener {
    static func open(_ url: URL) {
        if let log = UserDefaults.standard.string(forKey: "SmaltiOpenLog"), !log.isEmpty {
            appendLine(url.isFileURL ? url.path(percentEncoded: false) : url.absoluteString, to: URL(filePath: log))
            return
        }
        let workspace = NSWorkspace.shared
        // A `.toml` with no app for it opens in TextEdit rather than failing.
        guard workspace.urlForApplication(toOpen: url) == nil,
            let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Shows a saved file selected in Finder; with `-SmaltiOpenLog`, writes its path instead.
    static func reveal(_ file: URL) {
        if let log = UserDefaults.standard.string(forKey: "SmaltiOpenLog"), !log.isEmpty {
            appendLine(file.path(percentEncoded: false), to: URL(filePath: log))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// UI tests read this file; a write that fails is logged so a test that sees nothing has a cause to look at.
    private static func appendLine(_ line: String, to file: URL) {
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        do {
            try (existing + line + "\n").write(to: file, atomically: true, encoding: .utf8)
        } catch {
            Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "open")
                .error("could not write the open log: \(String(describing: error), privacy: .public)")
        }
    }
}
