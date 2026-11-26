/// F7.7: the prompt studio's and the prompt's own words (`Prompt.dc.html`).
public struct PromptCopy: Sendable, Equatable {
    public let modules: [PromptModuleID: String]
    /// The grey note after a module's title ("· últimos 2 niveles").
    public let moduleDetails: [PromptModuleID: String]
    public let templates: [PromptTemplate: String]
    public let symbolOnlyNote: String
    public let icons: [PromptIcons: String]
    public let twoLines: String
    public let shellPrompt: String
    public let noNerdFont: String
    public let previews: [PreviewSituation: String]
    /// What the agents module writes in the prompt: "● claude te espera", "● 2 te esperan".
    public let agentWaiting: String
    public let agentsWaiting: String
    public let agentFailed: String
    public let agentsFailed: String
    public let starshipDirectoryComment: String
    public let starshipAgentsComment: String

    public static let spanish = PromptCopy(
        modules: [
            .directory: "Directorio", .gitBranch: "Rama git", .gitStatus: "Cambios git", .runtime: "Runtime",
            .duration: "Duración", .agents: "Agentes que esperan", .time: "Hora",
            .cloud: "Contexto de Kubernetes / AWS",
        ],
        moduleDetails: [
            .directory: "últimos 2 niveles", .gitStatus: "●2 +1", .runtime: "Node, Bun, Python, Go",
            .duration: "si pasa de 2 s",
        ],
        templates: [
            .cleanLine: "Línea limpia", .singleLine: "Una sola línea", .pills: "Píldoras", .symbolOnly: "Solo símbolo",
        ],
        symbolOnlyNote: "· contexto en la cabecera",
        icons: [.thin: "Trazo fino", .nerd: "Nerd Font", .none: "Sin iconos"],
        twoLines: "Contexto arriba, input abajo", shellPrompt: "Prompt del shell",
        noNerdFont: "No hay una Nerd Font instalada",
        previews: [
            .normalFolder: "Carpeta normal", .nodeProject: "Proyecto Node con git",
            .afterErrorWithAgent: "Después de un error, con agente activo",
        ],
        agentWaiting: "te espera", agentsWaiting: "te esperan", agentFailed: "falló", agentsFailed: "fallaron",
        starshipDirectoryComment:
            "Directorio: Starship muestra dos niveles también dentro de un repositorio; Smalti lo muestra desde la raíz.",
        starshipAgentsComment: "Agentes que esperan: solo existe dentro de Smalti; no tiene equivalente en Starship.")

    public static let english = PromptCopy(
        modules: [
            .directory: "Directory", .gitBranch: "Git branch", .gitStatus: "Git changes", .runtime: "Runtime",
            .duration: "Duration", .agents: "Waiting agents", .time: "Time", .cloud: "Kubernetes / AWS context",
        ],
        moduleDetails: [
            .directory: "last 2 levels", .gitStatus: "●2 +1", .runtime: "Node, Bun, Python, Go",
            .duration: "if over 2 s",
        ],
        templates: [.cleanLine: "Clean line", .singleLine: "Single line", .pills: "Pills", .symbolOnly: "Symbol only"],
        symbolOnlyNote: "· context in the header",
        icons: [.thin: "Thin stroke", .nerd: "Nerd Font", .none: "No icons"],
        twoLines: "Context above, input below", shellPrompt: "Shell prompt", noNerdFont: "No Nerd Font is installed",
        previews: [
            .normalFolder: "Regular folder", .nodeProject: "Node project with git",
            .afterErrorWithAgent: "After an error, with an active agent",
        ],
        agentWaiting: "is waiting", agentsWaiting: "are waiting", agentFailed: "failed", agentsFailed: "failed",
        starshipDirectoryComment:
            "Directory: Starship shows two levels inside a repository too; Smalti shows it from the root.",
        starshipAgentsComment: "Waiting agents: it exists only inside Smalti; Starship has no equivalent.")
}
