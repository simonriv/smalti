import Foundation

/// F7.7: the same heuristic as `SmaltiCoreTestSupport.SpanishMarkers`, for texts read from the running app: Spanish
/// letters and marks, or a common Spanish word that is not English.
enum SpanishText {
    private static let letters = Set("áéíóúñÁÉÍÓÚÑ¿¡")
    private static let words: Set<String> = [
        "de", "del", "la", "las", "el", "los", "en", "con", "sin", "para", "por", "una", "que", "hace", "ahora",
        "panel", "paneles", "sesión", "sesiones", "ventana", "ventanas", "abrir", "cerrar", "buscar", "guardar",
        "mostrar", "activar", "desactivar", "ayuda", "nada", "todos", "todas", "hoy", "días", "línea", "tema",
        "temas", "registros", "archivo", "fallo", "aprobar", "rechazar", "espera", "esperan", "esperando",
        "trabajando", "detenido", "copiar", "pegar", "nuevo", "nueva", "siguiente", "anterior", "entrada", "salida",
        "costo", "caché",
    ]

    static func looksSpanish(_ text: String) -> Bool {
        if text.contains(where: { letters.contains($0) }) { return true }
        var tokens = text.lowercased().split(whereSeparator: { !$0.isLetter })
        // The snapshot cuts long values ("Secure Keyboard En..."): the cut word is not a word.
        if text.hasSuffix("...") || text.hasSuffix("…") { tokens = tokens.dropLast() }
        return tokens.contains { words.contains(String($0)) }
    }

    /// The labels, titles, values and placeholders of an accessibility snapshot (`debugDescription`), leaving out
    /// the terminal's own screen text.
    static func visibleTexts(in snapshot: String) -> [String] {
        let field =
            /(?:label|title|placeholderValue): '([^']*)'|value: (.+?)(?=, (?:label|title|placeholderValue|value|identifier|Selected|Disabled|Enabled): |$)/
        return snapshot.split(separator: "\n").filter { !$0.contains("smalti.terminal") }.flatMap { line in
            line.matches(of: field).compactMap { match in
                let text = String(match.output.1 ?? match.output.2 ?? "")
                return text.isEmpty ? nil : text
            }
        }
    }
}
