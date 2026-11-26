import Foundation

/// F7.7: a heuristic for "this English text still has Spanish in it": Spanish-only letters and marks, or a word
/// from a short list of common Spanish words that are not English. Shared by the catalog audit and the UI walk.
public enum SpanishMarkers {
    private static let letters = Set("áéíóúñÁÉÍÓÚÑ¿¡")
    public static let words: Set<String> = [
        "de", "del", "la", "las", "el", "los", "en", "con", "sin", "para", "por", "una", "que",
        "hace", "ahora", "panel", "paneles", "sesión", "sesiones", "ventana", "ventanas", "abrir", "cerrar", "buscar",
        "guardar", "mostrar", "activar", "desactivar", "ayuda", "nada", "todos", "todas", "hoy", "días", "línea",
        "tema", "temas", "registros", "archivo", "fallo", "aprobar", "rechazar", "espera", "esperan", "esperando",
        "trabajando", "detenido", "copiar", "pegar", "nuevo", "nueva", "siguiente", "anterior", "entrada", "salida",
        "costo", "caché",
    ]

    public static func looksSpanish(_ text: String, allowed: Set<String> = []) -> Bool {
        var remaining = text
        for word in allowed { remaining = remaining.replacingOccurrences(of: word, with: " ") }
        if remaining.contains(where: { letters.contains($0) }) { return true }
        let tokens = remaining.lowercased().split(whereSeparator: { !$0.isLetter })
        return tokens.contains { words.contains(String($0)) }
    }
}
