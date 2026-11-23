import Foundation

/// The one-line description of a tool call in the activity list ("pnpm lint --fix", "reminder.service.ts +18 −4").
public enum ToolSummary {
    private static let fileTools: Set<String> = ["Read", "Write", "Edit", "Update", "MultiEdit"]
    private static let searchTools: Set<String> = ["Grep", "Glob"]

    public static func text(name: String, input: [String: String], diff: DiffStat?) -> String {
        if name == "Bash" { return firstLine(of: input["command"] ?? "") }
        if fileTools.contains(name) { return fileText(input["file_path"], diff: diff) }
        if searchTools.contains(name) { return searchText(input) }
        return input.sorted { $0.key < $1.key }.first?.value ?? ""
    }

    /// A heredoc commit is one activity row, not six: the first line with text, trimmed.
    private static func firstLine(of command: String) -> String {
        let lines = command.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty } ?? ""
    }

    private static func fileText(_ path: String?, diff: DiffStat?) -> String {
        let file = path?.split(separator: "/").last.map(String.init) ?? ""
        guard let diff else { return file }
        return "\(file) +\(diff.added) −\(diff.removed)"
    }

    private static func searchText(_ input: [String: String]) -> String {
        let pattern = "\"\(input["pattern"] ?? "")\""
        guard let path = input["path"] else { return pattern }
        return "\(pattern) en \(path)"
    }
}
