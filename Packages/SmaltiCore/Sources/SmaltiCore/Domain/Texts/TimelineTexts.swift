/// F9: the timeline's words that the domain writes (who spoke, tool states, notes, empty states, search summaries).
public struct TimelineTexts: Sendable, Equatable {
    public let you: String
    public let done: String
    public let working: String
    public let error: String
    public let errorExit: TextTemplate
    public let output: String
    public let call: String
    public let moreLines: PluralText
    public let compacted: String
    public let compactedTokens: TextTemplate
    public let image: TextTemplate
    public let turns: PluralText
    public let tools: PluralText
    public let since: TextTemplate
    public let copied: TextTemplate
    public let projectScope: TextTemplate
    public let matches: PluralText
    public let inSessions: PluralText
    public let searching: String
    public let capped: TextTemplate
    public let noMatch: TextTemplate
    public let thisPane: String
    public let openIn: TextTemplate
    public let closed: TextTemplate
    public let noAgentTitle: String
    public let noAgentBody: String
    public let unreadableTitle: TextTemplate
    public let unreadableBody: String
    public let recent: TextTemplate
    public let noSessions: String
    public let unidentified: TextTemplate
    public let unidentifiedTag: String
    public let compressed: String
    public let missing: TextTemplate
    public let unreadable: TextTemplate
    public let loading: String

    public static let spanish = TimelineTexts(
        you: "Tú", done: "listo", working: "trabajando", error: "error", errorExit: "error · exit {code}",
        output: "Salida", call: "Llamada",
        moreLines: PluralText(
            one: "… {count} línea más · {copy} copia la salida íntegra",
            other: "… {count} líneas más · {copy} copia la salida íntegra"),
        compacted: "Conversación compactada", compactedTokens: "Conversación compactada · {before} → {after} tokens",
        image: "Imagen adjunta · {kind}",
        turns: PluralText(one: "{count} turno", other: "{count} turnos"),
        tools: PluralText(one: "{count} herramienta", other: "{count} herramientas"), since: "desde {time}",
        copied: "Copiado · {size}", projectScope: "Proyecto · {name}",
        matches: PluralText(one: "{count} coincidencia", other: "{count} coincidencias"),
        inSessions: PluralText(one: "en {count} sesión", other: "en {count} sesiones"),
        searching: "Buscando…", capped: "se muestran las primeras {count}",
        noMatch: "Nada coincide con «{query}» en este proyecto", thisPane: "este panel", openIn: "abierta en {pane}",
        closed: "cerrada · {when}", noAgentTitle: "Este panel no tiene un agente",
        noAgentBody:
            "El timeline muestra los turnos de Claude Code o de Codex del panel enfocado. Ábrelos aquí o elige una sesión del proyecto.",
        unreadableTitle: "{harness} no deja un transcript que Smalti sepa leer",
        unreadableBody:
            "El timeline lee Claude Code y Codex. Lo de este panel sigue en su terminal; puedes abrir otra sesión del proyecto o buscar en todas.",
        recent: "Sesiones recientes · {project}",
        noSessions: "Aún no hay sesiones de Claude Code ni de Codex en este proyecto",
        unidentified:
            "Smalti no sabe qué sesión de {harness} escribe este panel. Mostrando la más reciente de {directory}: puede no ser esta.",
        unidentifiedTag: "sin identificar", compressed: "comprimida por Codex",
        missing: "La sesión ya no está en {path}", unreadable: "No se pudo leer {path}: {reason}", loading: "Leyendo…")

    public static let english = TimelineTexts(
        you: "You", done: "done", working: "working", error: "error", errorExit: "error · exit {code}",
        output: "Output", call: "Call",
        moreLines: PluralText(
            one: "… {count} more line · {copy} copies the whole output",
            other: "… {count} more lines · {copy} copies the whole output"),
        compacted: "Conversation compacted", compactedTokens: "Conversation compacted · {before} → {after} tokens",
        image: "Attached image · {kind}", turns: PluralText(one: "{count} turn", other: "{count} turns"),
        tools: PluralText(one: "{count} tool", other: "{count} tools"), since: "since {time}",
        copied: "Copied · {size}", projectScope: "Project · {name}",
        matches: PluralText(one: "{count} match", other: "{count} matches"),
        inSessions: PluralText(one: "in {count} session", other: "in {count} sessions"),
        searching: "Searching…", capped: "showing the first {count}",
        noMatch: "Nothing matches “{query}” in this project", thisPane: "this pane", openIn: "open in {pane}",
        closed: "closed · {when}", noAgentTitle: "This pane has no agent",
        noAgentBody:
            "The timeline shows the Claude Code or Codex turns of the focused pane. Start one here or pick a session from this project.",
        unreadableTitle: "{harness} leaves no transcript Smalti can read",
        unreadableBody:
            "The timeline reads Claude Code and Codex. This pane’s work is still in its terminal; you can open another session of this project or search them all.",
        recent: "Recent sessions · {project}", noSessions: "No Claude Code or Codex sessions in this project yet",
        unidentified:
            "Smalti doesn’t know which {harness} session this pane writes. Showing the latest one in {directory}: it may not be this one.",
        unidentifiedTag: "unidentified", compressed: "compressed by Codex",
        missing: "The session is no longer at {path}",
        unreadable: "Couldn’t read {path}: {reason}", loading: "Reading…")
}
