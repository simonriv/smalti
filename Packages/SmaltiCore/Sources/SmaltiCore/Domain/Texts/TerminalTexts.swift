/// F7.7: closing confirmations, the scrollback search, `smalti img` and the updates toggle.
public struct TerminalTexts: Sendable, Equatable {
    public let closePane: String
    public let closePaneDetail: TextTemplate
    public let closeWorkspace: TextTemplate
    public let closeWindow: String
    public let quit: String
    /// What a busy pane runs when nothing better names it.
    public let aProcess: String
    public let processes: PluralText
    public let running: TextTemplate
    public let runningRest: TextTemplate
    public let quitDetail: TextTemplate
    public let inWindows: TextTemplate
    public let noResults: String
    public let unselectedMatch: TextTemplate
    public let selectedMatch: TextTemplate
    public let images: PluralText
    public let skipped: PluralText
    public let hidden: TextTemplate
    public let noImages: TextTemplate
    public let automaticUpdatesOn: String
    public let automaticUpdatesOff: String

    public static let spanish = TerminalTexts(
        closePane: "¿Cerrar el panel?",
        closePaneDetail: "{command} sigue en marcha. Si cierras el panel, el proceso termina.",
        closeWorkspace: "¿Cerrar el workspace “{name}”?", closeWindow: "¿Cerrar la ventana?", quit: "¿Salir de Smalti?",
        aProcess: "un proceso", processes: PluralText(one: "{count} proceso", other: "{count} procesos"),
        running: "Hay {processes} en marcha: {named}{rest}.", runningRest: " y {count} más",
        quitDetail: "Hay {processes} en marcha{place}. Al volver podrás retomarlos desde Reanudar.",
        inWindows: " en {count} ventanas", noResults: "Sin resultados", unselectedMatch: "– de {total}",
        selectedMatch: "{index} de {total}", images: PluralText(one: "{count} imagen", other: "{count} imágenes"),
        skipped: PluralText(one: "{count} omitida (no es imagen)", other: "{count} omitidas (no son imagen)"),
        hidden: "… y {count} más (máximo {limit})", noImages: "Sin imágenes en {source}",
        automaticUpdatesOn: "Actualizaciones automáticas activadas",
        automaticUpdatesOff: "Actualizaciones automáticas desactivadas")

    public static let english = TerminalTexts(
        closePane: "Close the pane?",
        closePaneDetail: "{command} is still running. If you close the pane, the process ends.",
        closeWorkspace: "Close the workspace “{name}”?", closeWindow: "Close the window?", quit: "Quit Smalti?",
        aProcess: "a process", processes: PluralText(one: "{count} process", other: "{count} processes"),
        running: "{processes} still running: {named}{rest}.", runningRest: " and {count} more",
        quitDetail: "{processes} still running{place}. When you come back you can pick them up from Resume.",
        inWindows: " in {count} windows", noResults: "No results", unselectedMatch: "– of {total}",
        selectedMatch: "{index} of {total}", images: PluralText(one: "{count} image", other: "{count} images"),
        skipped: PluralText(one: "{count} skipped (not an image)", other: "{count} skipped (not images)"),
        hidden: "… and {count} more (maximum {limit})", noImages: "No images in {source}",
        automaticUpdatesOn: "Automatic updates turned on",
        automaticUpdatesOff: "Automatic updates turned off")
}
