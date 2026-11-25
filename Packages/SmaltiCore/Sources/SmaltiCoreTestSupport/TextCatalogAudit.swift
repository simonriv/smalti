import SmaltiCore

/// F7.7: walks a catalog's Spanish and English values side by side with `Mirror` and reports what a translator
/// would get wrong: an empty field, different placeholders, different dictionary keys, or Spanish left in English.
public enum TextCatalogAudit {
    public static func problems(spanish: Any, english: Any, allowed: Set<String> = []) -> [String] {
        compare(spanish, english, path: "", allowed: allowed)
    }

    private static func compare(_ spanish: Any, _ english: Any, path: String, allowed: Set<String>) -> [String] {
        switch (spanish, english) {
        case let (es as String, en as String):
            return strings(es, en, placeholders: ([], []), path: path, allowed: allowed)
        case let (es as TextTemplate, en as TextTemplate):
            return strings(
                es.raw, en.raw, placeholders: (es.placeholders, en.placeholders), path: path, allowed: allowed)
        case let (es as PluralText, en as PluralText):
            return compare(es.one, en.one, path: join(path, "one"), allowed: allowed)
                + compare(es.other, en.other, path: join(path, "other"), allowed: allowed)
        default:
            return composite(spanish, english, path: path, allowed: allowed)
        }
    }

    private static func composite(_ spanish: Any, _ english: Any, path: String, allowed: Set<String>) -> [String] {
        let es = Mirror(reflecting: spanish)
        let en = Mirror(reflecting: english)
        if es.displayStyle == .dictionary {
            let esPairs = pairs(es)
            let enPairs = pairs(en)
            guard Set(esPairs.keys) == Set(enPairs.keys) else { return ["\(path): keys differ"] }
            return esPairs.keys.sorted().flatMap { key in
                compare(esPairs[key] as Any, enPairs[key] as Any, path: "\(path)[\(key)]", allowed: allowed)
            }
        }
        return zip(es.children, en.children).flatMap { esChild, enChild in
            compare(esChild.value, enChild.value, path: join(path, esChild.label ?? "?"), allowed: allowed)
        }
    }

    /// Dictionary entries by the description of their key, so any `Hashable` key compares.
    private static func pairs(_ mirror: Mirror) -> [String: Any] {
        var result: [String: Any] = [:]
        for child in mirror.children {
            let pair = Mirror(reflecting: child.value).children.map(\.value)
            guard pair.count == 2 else { continue }
            result[String(describing: pair[0])] = pair[1]
        }
        return result
    }

    private static func strings(
        _ es: String, _ en: String, placeholders: (Set<String>, Set<String>), path: String, allowed: Set<String>
    ) -> [String] {
        var found: [String] = []
        if es.isEmpty { found.append("\(path): empty in Spanish") }
        if en.isEmpty { found.append("\(path): empty in English") }
        if placeholders.0 != placeholders.1 {
            let list = { (names: Set<String>) in names.sorted().joined(separator: ", ") }
            found.append("\(path): placeholders differ (es: \(list(placeholders.0)); en: \(list(placeholders.1)))")
        }
        if SpanishMarkers.looksSpanish(en, allowed: allowed) {
            found.append("\(path): looks Spanish in English (“\(en)”)")
        }
        return found
    }

    private static func join(_ path: String, _ label: String) -> String {
        path.isEmpty ? label : "\(path).\(label)"
    }
}
