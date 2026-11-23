import Foundation
import SmaltiCore

/// Writes each notice as one JSON line (`pane`, `title`, `body`). UI tests read it instead of macOS notifications,
/// which a test cannot observe (`-SmaltiNotificationLog <file>`).
@MainActor
public final class FileLogNotifier: Notifier {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func notify(_ notice: AttentionNotice) {
        let object = ["pane": notice.pane.description, "title": notice.title, "body": notice.body]
        guard var line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }

    /// The notices written so far, in order.
    public static func read(_ file: URL) -> [AttentionNotice] {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String],
                let pane = object["pane"].flatMap(UUID.init(uuidString:)), let title = object["title"],
                let body = object["body"]
            else { return nil }
            return AttentionNotice(pane: PaneID(rawValue: pane), title: title, body: body)
        }
    }
}
