import Foundation

/// Why exporting or importing a layout failed: its file, or the saved layouts.
public enum LayoutShareError: Error, Equatable, Sendable {
    case file(LayoutFileError)
    case archive(SessionArchiveError)

    /// The reason after "No se pudo exportar/importar el layout: ".
    public func message(_ texts: SessionTexts) -> String {
        switch self {
        case .file(let error): error.message(texts)
        case .archive(.notFound(let name)): texts.notFound(["name": name])
        case .archive(.writeFailed(let file, let reason)): texts.saveFailed(["file": file, "reason": reason])
        case .archive(.newerFormat(let file, let version)):
            texts.savedByNewer(["file": file, "version": String(version)])
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
/// One command a shared layout runs, and where when it is not the layout's root ("make en api").
public struct PlannedCommand: Codable, Equatable, Sendable {
    public let command: String
    public let place: String?

    public init(command: String, place: String?) {
        self.command = command
        self.place = place
    }

    public func text(_ texts: SessionTexts) -> String {
        place.map { texts.located(["command": command, "place": $0]) } ?? command
    }
}

public struct ImportPreview: Equatable, Sendable {
    public let name: LayoutName
    /// What the layout runs when opened, one per pane that runs something, as typed in the shell.
    public let commands: [PlannedCommand]
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

    public func preview(_ file: URL, root chosen: String? = nil) throws(LayoutShareError) -> ImportPreview {
        let shared: SharedLayout
        do { shared = try files.read(from: file) } catch { throw .file(error) }
        let validated: ValidatedLayout
        do { validated = try shared.validated() } catch { throw .file(.invalid(error)) }
        // The folder picked for a root this Mac lacks: the confirmation then shows the paths that will run.
        let root = chosen ?? validated.layout.resolvedRoot(home: home)
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
    private func commands(of layout: SharedLayout, root: String) -> [PlannedCommand] {
        layout.workspaceSnapshot(root: root, home: home).panes.compactMap { pane in
            let command: String? =
                switch PaneLaunch.saved(pane) {
                case .shell: nil
                case .relaunch(let command): command.displayText
                case .editor(let position): position.plainCommand
                case .resume(let agent): harnesses.adapter(for: agent.harness)?.continueCommand()
                }
            return command.map { located($0, in: pane.workingDirectory, root: root) }
        }
    }

    /// "make en api", "claude --continue en ~/.ssh": a command that does not run in the layout's root says where.
    private func located(_ command: String, in directory: String, root: String) -> PlannedCommand {
        guard let place = PortablePaths.relative(directory, to: root) else {
            return PlannedCommand(command: command, place: PortablePaths(home: home).portable(directory))
        }
        return PlannedCommand(command: command, place: place == "." ? nil : place)
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
    public static func confirmationTitle(_ name: LayoutName, texts: SessionTexts) -> String {
        texts.importTitle(["name": name.rawValue])
    }

    public static func confirmationBody(_ preview: ImportPreview, texts: SessionTexts) -> String {
        let commands =
            preview.commands.isEmpty
            ? texts.opensOnlyShells
            : texts.willRun(["commands": preview.commands.map { $0.text(texts) }.joined(separator: " · ")])
        return ([commands] + preview.warnings.map { warning($0, texts: texts) }).joined(separator: "\n")
    }

    public static func folderPrompt(_ name: LayoutName, texts: SessionTexts) -> String {
        texts.folderPrompt(["name": name.rawValue])
    }

    private static func warning(_ warning: SharedLayoutWarning, texts: SessionTexts) -> String {
        switch warning {
        case .unknownHarness(let pane, let name): texts.unknownHarness(["pane": String(pane), "name": name])
        case .unknownLayout(let layout): texts.unknownLayout(["layout": layout])
        }
    }
}
