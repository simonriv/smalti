import Foundation

/// Finds where a key is written in the raw TOML text, so semantic errors can name a line even though the TOML
/// library only reports lines for syntax errors.
///
/// It reads line by line without a TOML parser, so text inside a multiline string (`"""…"""` or `'''…'''`)
/// that looks like `key = …` or `[table]` can be taken for one. Inline tables and dotted keys are not placed.
enum TOMLKeyLocator {
    /// The 1-based line where `key = …` appears inside `[table]` (`""` for the top level, before any header), or
    /// where `[table.key]` is declared. Comments and other tables are skipped; quoted keys are compared unquoted.
    static func line(of key: String, inTable table: String, text: String) -> Int? {
        let header = table.isEmpty ? key : "\(table).\(key)"
        var currentTable = ""
        for (index, rawLine) in lines(of: text).enumerated() {
            let line = rawLine.trimmingWhitespace()
            if let name = tableHeader(in: line) {
                if name == header { return index + 1 }
                currentTable = name
            } else if currentTable == table, assignedKey(in: line) == key {
                return index + 1
            }
        }
        return nil
    }

    /// Splits on any line break; `\r\n` is a single `Character` in Swift, so splitting on `"\n"` would miss it.
    private static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    /// `name` for `[name]` or `[[name]]`, ignoring a trailing comment. Quoted segments are unquoted and may hold
    /// dots or brackets (`[observatory.models."qwen3.5:9b[1m]"]` → `observatory.models.qwen3.5:9b[1m]`), the same
    /// dotted name `TOMLSection` builds.
    private static func tableHeader(in line: Substring) -> String? {
        guard line.hasPrefix("[") else { return nil }
        var segments: [String] = []
        var current = ""
        var quote: Character?
        for character in line.drop(while: { $0 == "[" }) {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "]" {
                break
            } else if character == "." {
                segments.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current.trimmingCharacters(in: .whitespaces))
        return segments.joined(separator: ".")
    }

    /// The key of `key = value`, unquoted, or `nil` for comments and blank lines.
    private static func assignedKey(in line: Substring) -> String? {
        guard let first = line.first, first != "#" else { return nil }
        let key: Substring
        let rest: Substring
        if first == "\"" || first == "'" {
            let body = line.dropFirst()
            guard let end = body.firstIndex(of: first) else { return nil }
            key = body[..<end]
            rest = body[body.index(after: end)...]
        } else {
            guard let equals = line.firstIndex(of: "=") else { return nil }
            key = line[..<equals].trimmingWhitespace()
            rest = line[equals...]
        }
        return rest.trimmingWhitespace().hasPrefix("=") ? String(key) : nil
    }
}

extension Substring {
    fileprivate func trimmingWhitespace() -> Substring {
        guard let start = firstIndex(where: { !$0.isWhitespace }), let end = lastIndex(where: { !$0.isWhitespace })
        else { return self[endIndex...] }
        return self[start...end]
    }
}
