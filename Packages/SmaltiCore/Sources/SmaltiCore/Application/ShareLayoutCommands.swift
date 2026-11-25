import Foundation

/// Why exporting or importing a layout failed: its file, or the saved layouts.
public enum LayoutShareError: Error, Equatable, Sendable {
    case file(LayoutFileError)
    case archive(SessionArchiveError)

    /// The reason after "No se pudo exportar/importar el layout: ".
    public var message: String {
        switch self {
        case .file(let error): error.message
        case .archive(.notFound(let name)): "no hay ningún layout guardado como «\(name)»"
        case .archive(.writeFailed(let file, let reason)): "no se pudo guardar \(file) (\(reason))"
        }
    }
}

/// Writes a saved layout as a portable file (spec F7).
@MainActor
public struct ExportLayout {
    private let layouts: any NamedLayouts
    private let files: any LayoutFiles
    private let home: String

    public init(layouts: any NamedLayouts, files: any LayoutFiles, home: String) {
        self.layouts = layouts
        self.files = files
        self.home = home
    }

    public func execute(_ name: LayoutName, to file: URL) throws(LayoutShareError) {
        let saved: WorkspaceSnapshot
        do { saved = try layouts.layout(named: name) } catch { throw .archive(error) }
        do { try files.write(SharedLayout(exporting: saved, named: name, home: home), to: file) } catch {
            throw .file(error)
        }
    }
}

/// What importing a file would do, shown before anything is saved.
public struct ImportPreview: Equatable, Sendable {
    public let name: LayoutName
    /// What the layout runs when opened, one per pane that runs something, as typed in the shell.
    public let commands: [String]
    /// The root on this machine (`~` resolved).
    public let root: String
    public let isRootPresent: Bool
    public let warnings: [SharedLayoutWarning]
    public let layout: SharedLayout
}

/// Imports a shared layout file in two steps, so the user sees its commands first: `preview`, then `confirm`.
@MainActor
public struct ImportLayout {
    private let layouts: any NamedLayouts
    private let files: any LayoutFiles
    private let harnesses: HarnessRegistry
    private let home: String
    private let directoryExists: @Sendable (String) -> Bool

    public init(
        layouts: any NamedLayouts, files: any LayoutFiles, harnesses: HarnessRegistry, home: String,
        directoryExists: @escaping @Sendable (String) -> Bool
    ) {
        self.layouts = layouts
        self.files = files
        self.harnesses = harnesses
        self.home = home
        self.directoryExists = directoryExists
    }

    public func preview(_ file: URL) throws(LayoutShareError) -> ImportPreview {
        let validated: ValidatedLayout
        do { validated = try files.read(from: file).validated() } catch let error as LayoutFileError {
            throw .file(error)
        } catch let error as SharedLayoutError {
            throw .file(.invalid(error))
        } catch {
            throw .file(.unreadable(path: file.path(percentEncoded: false), reason: "\(error)"))
        }
        let root = validated.layout.resolvedRoot(home: home)
        return ImportPreview(
            name: validated.name, commands: commands(of: validated.layout, root: root), root: root,
            isRootPresent: directoryExists(root), warnings: validated.warnings, layout: validated.layout)
    }

    /// Saves the previewed layout under `root`, with the first free name ("solen-dev", "solen-dev 2"…).
    public func confirm(_ preview: ImportPreview, root: String) throws(LayoutShareError) -> LayoutName {
        let name = freeName(for: preview.name)
        do { try layouts.save(preview.layout.workspaceSnapshot(root: root, home: home), as: name) } catch {
            throw .archive(error)
        }
        return name
    }

    /// What each pane will run, read through `PaneLaunch.saved`: the same choice restoring makes.
    private func commands(of layout: SharedLayout, root: String) -> [String] {
        layout.workspaceSnapshot(root: root, home: home).panes.compactMap { pane in
            switch PaneLaunch.saved(pane) {
            case .shell: nil
            case .relaunch(let command): command.displayText
            case .editor(let position): position.plainCommand
            case .resume(let agent): harnesses.adapter(for: agent.harness)?.continueCommand()
            }
        }
    }

    private func freeName(for name: LayoutName) -> LayoutName {
        let taken = Set(layouts.names().map { $0.rawValue.lowercased() })
        guard taken.contains(name.rawValue.lowercased()) else { return name }
        var number = 2
        while true {
            let suffix = " \(number)"
            let base = String(name.rawValue.prefix(LayoutName.maximumLength - suffix.count))
            // A prefix of a valid name plus " N" is valid: no separator, dot start or control character is added.
            if let candidate = try? LayoutName(base + suffix), !taken.contains(candidate.rawValue.lowercased()) {
                return candidate
            }
            number += 1
        }
    }
}

/// The import's words, as the spec writes them.
public enum ImportTexts {
    public static func confirmationTitle(_ name: LayoutName) -> String { "¿Importar el layout “\(name.rawValue)”?" }

    public static func confirmationBody(_ preview: ImportPreview) -> String {
        let commands =
            preview.commands.isEmpty
            ? "Al abrirlo solo abrirá shells." : "Al abrirlo ejecutará: " + preview.commands.joined(separator: " · ")
        return ([commands] + preview.warnings.map(warning)).joined(separator: "\n")
    }

    public static func folderPrompt(_ name: LayoutName) -> String {
        "Elige la carpeta de “\(name.rawValue)” en este Mac"
    }

    private static func warning(_ warning: SharedLayoutWarning) -> String {
        switch warning {
        case .unknownHarness(let pane, let name):
            "El panel \(pane) usa un harness desconocido (\(name)): se abrirá como shell."
        case .unknownLayout(let layout): "Layout desconocido (\(layout)): se usará Dwindle."
        }
    }
}
