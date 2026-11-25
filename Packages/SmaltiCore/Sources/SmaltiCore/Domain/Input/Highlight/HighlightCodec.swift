/// `highlight <seq> <spans>`: each span is `start,end,role`, separated by spaces. An answer never exceeds
/// `InputProtocol.maximumAnswerBytes` with its newline: the spans that do not fit are left out, from the end of the
/// line, and never split; the rest of the line stays uncolored (spec F5.6).
public enum HighlightCodec {
    public static func encode(_ spans: [HighlightSpan], seq: Int) -> String {
        let head = "highlight\t\(seq)\t"
        var budget = InputProtocol.maximumAnswerBytes - 1 - head.utf8.count
        var fields: [String] = []
        for span in spans {
            let field = "\(span.range.lowerBound),\(span.range.upperBound),\(span.role.rawValue)"
            let cost = field.utf8.count + (fields.isEmpty ? 0 : 1)
            guard cost <= budget else { break }
            budget -= cost
            fields.append(field)
        }
        return head + fields.joined(separator: " ")
    }
}
