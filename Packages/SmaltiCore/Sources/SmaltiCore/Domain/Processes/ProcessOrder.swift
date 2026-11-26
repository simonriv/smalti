import Foundation

/// How the process view is sorted; ⌘⇧S moves to the next one.
public enum ProcessOrder: CaseIterable, Equatable, Sendable {
    case cpu
    case memory
    case name
    case pid

    public var next: ProcessOrder { Self.allCases.cycled(after: self) }
}

/// How the port view is sorted; ⌘⇧S moves to the next one.
public enum PortOrder: CaseIterable, Equatable, Sendable {
    case port
    case process
    case pane

    public var next: PortOrder { Self.allCases.cycled(after: self) }
}

extension Array where Element: Equatable {
    fileprivate func cycled(after element: Element) -> Element {
        guard let index = firstIndex(of: element) else { return self[0] }
        return self[(index + 1) % count]
    }
}

/// Matches the filter words, all of them, ignoring case and accents.
struct TextFilter {
    private let words: [String]

    init(_ filter: String) {
        words = Self.folded(filter).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { words.isEmpty }

    func matches(_ fields: [String]) -> Bool {
        let haystack = Self.folded(fields.joined(separator: " "))
        return words.allSatisfy(haystack.contains)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
