/// F8.5: the projects' words that the domain writes (confirmation, selector, status bar, errors).
public struct ProjectTexts: Sendable, Equatable {
    public let openTitle: TextTemplate
    public let firstTime: String
    public let changedSince: TextTemplate
    public let arrangementChanged: TextTemplate
    public let sameCommands: String
    public let source: TextTemplate
    public let openAndRun: String
    public let cancel: String
    public let replaceTitle: String
    public let replaceBody: TextTemplate
    public let replaceNote: String
    public let replace: String
    public let shellOnly: String
    public let inThisPane: String
    public let openInWorkspace: TextTemplate
    public let openInAnotherWindow: String
    public let openBadge: TextTemplate
    public let searchPlaceholder: String
    public let empty: String
    public let noMatch: TextTemplate
    public let dropsOff: String
    public let choose: String
    public let openOrGo: String
    public let next: String
    public let close: String
    public let opened: TextTemplate
    public let openFailed: TextTemplate
    public let saved: TextTemplate
    public let saveFailed: TextTemplate
    public let missing: TextTemplate
    public let unreadable: TextTemplate
    public let notRegularFile: TextTemplate
    public let unwritable: TextTemplate
    public let projects: String

    public static let spanish = ProjectTexts(
        openTitle: "¿Abrir el proyecto “{name}”?",
        firstTime: "Es la primera vez que abres este layout. Al abrirlo ejecutará:",
        changedSince: "El layout cambió desde que lo aprobaste ({date}). Al abrirlo ejecutará:",
        arrangementChanged:
            "También cambió la disposición: {panes} paneles en {layout} (antes {beforePanes} en {beforeLayout}).",
        sameCommands: "Los comandos son los mismos; cambiaron otros detalles del archivo.",
        source:
            "Viene de {root}/.smalti/layout.json. Sin aprobar no se ejecuta nada; Smalti recuerda lo que apruebes, nunca en el repo.",
        openAndRun: "abrir y ejecutar", cancel: "cancelar", replaceTitle: "Guardar layout del proyecto",
        replaceBody: "{root} ya tiene .smalti/layout.json. Reemplazarlo con este workspace:",
        replaceNote:
            "Se escribe en el repo para compartirlo con quien lo clone; no lleva sesiones, salida ni la ruta de tu home.",
        replace: "reemplazar", shellOnly: "shell", inThisPane: "en este panel",
        openInWorkspace: "abierto en el workspace {number}", openInAnotherWindow: "abierto en otra ventana",
        openBadge: "abierto · workspace {number}", searchPlaceholder: "Buscar proyecto",
        empty: "Aún no hay proyectos. Un repo con .smalti/layout.json aparece aquí al abrirlo.",
        noMatch: "Ningún proyecto coincide con «{query}»", dropsOff: "Los que ya no existen se quitan solos",
        choose: "elegir", openOrGo: "abrir o ir", next: "siguiente", close: "cerrar",
        opened: "Proyecto “{name}” abierto", openFailed: "No se pudo abrir el proyecto: {reason}",
        saved: "Layout del proyecto “{name}” guardado en .smalti/layout.json",
        saveFailed: "No se pudo guardar el layout del proyecto: {reason}",
        missing: "{root} ya no tiene .smalti/layout.json", unreadable: "no se pudo leer {root}: {reason}",
        notRegularFile: "{root}/.smalti/layout.json no es un archivo normal (¿un enlace?)",
        unwritable: "no se pudo escribir {path}: {reason}", projects: "Proyectos")

    public static let english = ProjectTexts(
        openTitle: "Open the project “{name}”?",
        firstTime: "This is the first time you open this layout. Opening it will run:",
        changedSince: "The layout changed since you approved it ({date}). Opening it will run:",
        arrangementChanged:
            "The arrangement changed too: {panes} panes in {layout} (was {beforePanes} in {beforeLayout}).",
        sameCommands: "The commands are the same; other details of the file changed.",
        source:
            "From {root}/.smalti/layout.json. Nothing runs unless you approve; Smalti remembers what you approve, never in the repo.",
        openAndRun: "open and run", cancel: "cancel", replaceTitle: "Save Project Layout",
        replaceBody: "{root} already has .smalti/layout.json. Replace it with this workspace:",
        replaceNote:
            "It is written into the repo to share with whoever clones it; it carries no sessions, output or your home path.",
        replace: "replace", shellOnly: "shell", inThisPane: "in this pane",
        openInWorkspace: "open in workspace {number}", openInAnotherWindow: "open in another window",
        openBadge: "open · workspace {number}", searchPlaceholder: "Search projects",
        empty: "No projects yet. A repo with .smalti/layout.json shows up here once you open it.",
        noMatch: "No project matches “{query}”", dropsOff: "Projects that no longer exist drop off",
        choose: "choose", openOrGo: "open or go", next: "next", close: "close",
        opened: "Project “{name}” opened", openFailed: "Couldn’t open the project: {reason}",
        saved: "Project layout “{name}” saved to .smalti/layout.json",
        saveFailed: "Couldn’t save the project layout: {reason}",
        missing: "{root} no longer has .smalti/layout.json", unreadable: "couldn’t read {root}: {reason}",
        notRegularFile: "{root}/.smalti/layout.json isn’t a regular file (a link?)",
        unwritable: "couldn’t write {path}: {reason}", projects: "Projects")
}

extension ProjectFileError {
    /// The reason after "No se pudo abrir/guardar…: ".
    public func message(_ texts: ProjectTexts, layout: SharedLayoutErrorTexts) -> String {
        switch self {
        case .missing(let root): texts.missing(["root": root])
        case .unreadable(let root, let reason): texts.unreadable(["root": root, "reason": reason])
        case .notRegularFile(let root): texts.notRegularFile(["root": root])
        case .invalid(let error): error.message(layout)
        case .unwritable(let path, let reason): texts.unwritable(["path": path, "reason": reason])
        }
    }
}
