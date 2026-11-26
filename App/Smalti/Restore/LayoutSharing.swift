import AppKit
import SmaltiCore

/// Primary adapter for shared layouts (spec F7): the save, open and folder panels and the import confirmation, over
/// `ExportLayout` and `ImportLayout`. In Debug builds, UI tests replace each panel with a launch argument.
@MainActor
final class LayoutSharing {
    private static let exportDirectoryKey = "SmaltiExportDirectory"
    private static let importFileKey = "SmaltiImportFile"
    private static let pickedFolderKey = "SmaltiPickedFolder"
    private static let confirmImportKey = "SmaltiConfirmImport"

    private let export: ExportLayout
    private let importer: ImportLayout

    init(layouts: any NamedLayouts, files: any LayoutFiles, harnesses: HarnessRegistry, home: String) {
        export = ExportLayout(layouts: layouts, files: files, home: home)
        importer = ImportLayout(
            layouts: layouts, files: files, harnesses: harnesses, home: home,
            directoryExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            })
    }

    // MARK: Export

    func export(_ name: LayoutName, from window: NSWindow, report: @escaping (StatusMessage) -> Void) {
        let fileName = "\(name.rawValue).\(SharedLayout.fileExtension)"
        if let folder = Self.testValue(Self.exportDirectoryKey) {
            write(name, to: URL(filePath: folder).appending(path: fileName), report: report)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        // The panel itself asks before replacing an existing file.
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.write(name, to: url, report: report) }
        }
    }

    private func write(_ name: LayoutName, to file: URL, report: (StatusMessage) -> Void) {
        do {
            try export.execute(name, to: file)
            report(.layoutExported(name.rawValue))
        } catch {
            report(.layoutExportFailed(error.message(.current)))
        }
    }

    // MARK: Import

    func importLayout(in window: NSWindow, report: @escaping (StatusMessage) -> Void) {
        chooseFile(in: window) { [weak self] file in self?.preview(file, in: window, report: report) }
    }

    private func chooseFile(in window: NSWindow, then use: @escaping (URL) -> Void) {
        if let path = Self.testValue(Self.importFileKey) { return use(URL(filePath: path)) }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { use(url) }
        }
    }

    /// Reads the file; when its root is missing here, asks for the folder first, so the confirmation shows the paths
    /// that will really run (review 2); then confirms and saves.
    private func preview(_ file: URL, in window: NSWindow, report: @escaping (StatusMessage) -> Void) {
        let first: ImportPreview
        do { first = try importer.preview(file) } catch {
            report(.layoutImportFailed(error.message(.current)))
            return
        }
        chooseRoot(for: first, in: window) { [weak self] root in
            guard let self else { return }
            let preview: ImportPreview
            switch rooted(first, file: file, root: root) {
            case .success(let value): preview = value
            case .failure(let error):
                report(.layoutImportFailed(error.message(.current)))
                return
            }
            confirm(preview, in: window) { [weak self] isConfirmed in
                guard isConfirmed else { return }
                self?.save(preview, root: root, report: report)
            }
        }
    }

    /// The preview again under the folder the user picked; the first one when the root was there already.
    private func rooted(_ first: ImportPreview, file: URL, root: String) -> Result<ImportPreview, LayoutShareError> {
        guard root != first.root else { return .success(first) }
        do { return .success(try importer.preview(file, root: root)) } catch { return .failure(error) }
    }

    /// "¿Importar el layout “…”?" with every command it will run; nothing is saved without "Importar".
    private func confirm(_ preview: ImportPreview, in window: NSWindow, then answer: @escaping (Bool) -> Void) {
        if let value = Self.testValue(Self.confirmImportKey) { return answer(value == "yes") }
        let alert = NSAlert()
        alert.messageText = ImportTexts.confirmationTitle(preview.name, texts: .current)
        alert.informativeText = ImportTexts.confirmationBody(preview, texts: .current)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Importar")
        let cancel = alert.addButton(withTitle: "Cancelar")
        cancel.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in answer(response == .alertFirstButtonReturn) }
    }

    /// The layout's root when it exists on this Mac; otherwise the folder the user picks (cancelling imports nothing).
    private func chooseRoot(for preview: ImportPreview, in window: NSWindow, then use: @escaping (String) -> Void) {
        guard !preview.isRootPresent else { return use(preview.root) }
        if let path = Self.testValue(Self.pickedFolderKey) { return use(path) }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = ImportTexts.folderPrompt(preview.name, texts: .current)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { use(url.path(percentEncoded: false)) }
        }
    }

    private func save(_ preview: ImportPreview, root: String, report: (StatusMessage) -> Void) {
        do {
            let name = try importer.confirm(preview, root: root)
            report(.layoutImported(name.rawValue))
        } catch {
            report(.layoutImportFailed(error.message(.current)))
        }
    }

    /// Debug builds only: UI tests answer the panels with launch arguments; the daily build always asks.
    private static func testValue(_ key: String) -> String? {
        #if DEBUG
            UserDefaults.standard.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
        #else
            nil
        #endif
    }
}
