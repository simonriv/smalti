import AppKit
import FileSessionAdapter
import SmaltiCore

/// F8.5, the projects across the app's windows: lists them for ⌘K and ⌘O, opens one (jumping to its workspace in
/// whichever window has it), asks before running what the user has not approved, and saves the active workspace as
/// the repo's `.smalti/layout.json`. Decisions are the use cases'; this only reads the windows and shows the result.
@MainActor
final class ProjectsCoordinator {
    private let files: any ProjectFiles
    private let records: any ProjectRecords
    private let harnesses: HarnessRegistry
    private let home: String
    private let windows: () -> [WindowComposition]

    init(
        files: any ProjectFiles, records: any ProjectRecords, harnesses: HarnessRegistry, home: String,
        windows: @escaping () -> [WindowComposition]
    ) {
        self.files = files
        self.records = records
        self.harnesses = harnesses
        self.home = home
        self.windows = windows
    }

    private var list: ListProjects { ListProjects(files: files, records: records, home: home) }

    private var opener: OpenProject {
        OpenProject(files: files, records: records, harnesses: harnesses, home: home, clock: { Date() })
    }

    private var saver: SaveProjectLayout {
        SaveProjectLayout(files: files, records: records, harnesses: harnesses, home: home, clock: { Date() })
    }

    /// What ⌘K offers in `composition`: the projects and where "Guardar layout del proyecto" would write.
    func catalog(for composition: WindowComposition) -> CatalogProjects {
        let controller = composition.controller
        let focused = controller.paneDirectories.focused
        return CatalogProjects(
            listings: listings(for: composition), home: home,
            saveRoot: focused.map { saver.root(of: controller.set.active, focusedDirectory: $0) })
    }

    /// ⌘O in `composition`.
    func showRecents(in composition: WindowComposition) {
        let selector = ProjectSelector(
            listings: listings(for: composition), activeProject: composition.controller.set.active.project,
            context: .init(home: home, now: Date(), texts: .current, time: .current))
        composition.closeOverlays(keeping: .projects)
        composition.projects?.showRecents(selector, theme: composition.controller.theme) { [weak self] root in
            self?.open(root, from: composition)
        }
    }

    /// Opens or jumps to the project at `root`, after the confirmation when it is needed.
    func open(_ root: String, from composition: WindowComposition) {
        let step: ProjectStep
        do { step = try opener.prepare(root: root, open: openWorkspaces(from: composition)) } catch {
            report(.openFailed, error.message(.current, layout: .current), in: composition)
            return
        }
        switch step {
        case .jump(let workspace): jump(to: workspace, root: root, from: composition)
        case .open(let prepared): run(prepared, in: composition)
        case .confirm(let confirmation):
            let card = ProjectCard.opening(
                confirmation,
                context: .init(
                    home: home, now: Date(), texts: .current, session: .current,
                    layoutNames: CommandTexts.current.layoutNames))
            composition.closeOverlays(keeping: .projects)
            composition.projects?.confirm(card, theme: composition.controller.theme) { [weak self] in
                self?.run(confirmation.prepared, in: composition)
            }
        }
    }

    /// "Guardar layout del proyecto" from the active workspace of `composition`.
    func save(from composition: WindowComposition) {
        let controller = composition.controller
        guard let focused = controller.paneDirectories.focused else { return }
        let step: ProjectSaveStep
        do { step = try saver.prepare(controller.set.active, focusedDirectory: focused) } catch {
            report(.saveFailed, error.message(.current, layout: .current), in: composition)
            return
        }
        switch step {
        case .write(let pending): write(pending, in: composition)
        case .confirmReplace(let pending):
            let card = ProjectCard.replacing(pending, context: .init(home: home, texts: .current))
            composition.closeOverlays(keeping: .projects)
            composition.projects?.confirm(card, theme: controller.theme) { [weak self] in
                self?.write(pending, in: composition)
            }
        }
    }

    private func listings(for composition: WindowComposition) -> [ProjectListing] {
        do { try list.forgetMissing() } catch {
            report(.openFailed, error.message(.current, layout: .current), in: composition)
        }
        let directories = composition.controller.paneDirectories
        return list.execute(
            paneDirectories: directories.all, focusedDirectory: directories.focused,
            open: openWorkspaces(from: composition))
    }

    private func openWorkspaces(from composition: WindowComposition) -> [OpenProjectWorkspace] {
        windows().flatMap { $0.controller.openWorkspaces(isThisWindow: $0 === composition) }
    }

    private func jump(to workspace: WorkspaceID, root: String, from composition: WindowComposition) {
        guard let owner = windows().first(where: { $0.controller.goTo(workspace) }) else { return }
        owner.window.makeKeyAndOrderFront(nil)
        do { try opener.jumped(to: root) } catch {
            report(.openFailed, error.message(.current, layout: .current), in: owner)
        }
    }

    private func run(_ prepared: PreparedProject, in composition: WindowComposition) {
        guard composition.controller.openProject(prepared) else { return }
        do { try opener.opened(prepared) } catch {
            report(.openFailed, error.message(.current, layout: .current), in: composition)
            return
        }
        composition.controller.report(
            StatusMessage(text: ProjectTexts.current.opened(["name": prepared.name.rawValue]), isTransient: true))
    }

    private func write(_ pending: PendingProjectSave, in composition: WindowComposition) {
        let name: LayoutName
        do { name = try saver.write(pending) } catch {
            report(.saveFailed, error.message(.current, layout: .current), in: composition)
            return
        }
        composition.controller.markActiveProject(pending.root)
        composition.controller.report(
            StatusMessage(text: ProjectTexts.current.saved(["name": name.rawValue]), isTransient: true))
    }

    private enum Failure { case openFailed, saveFailed }

    private func report(_ failure: Failure, _ reason: String, in composition: WindowComposition) {
        let texts = ProjectTexts.current
        let template = failure == .openFailed ? texts.openFailed : texts.saveFailed
        composition.controller.report(StatusMessage(text: template(["reason": reason]), isTransient: true))
    }
}
