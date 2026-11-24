import AppKit
import Quartz

/// ⌘Y (spec F5.5): the previewed image in the system's Quick Look panel. The window takes the panel's control while
/// it shows one file; ⌘Y again (or Esc, the panel's own) closes it.
@MainActor
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    private(set) var url: URL?

    /// Closes the panel when it shows; otherwise opens it on `path`, if any.
    func toggle(_ path: String?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard let path else { return }
        url = URL(fileURLWithPath: path)
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    /// The window gave the panel up (another window took it): this source has nothing to show any more.
    func clear() {
        url = nil
    }

    // Quick Look asks its data source on the main thread, as AppKit does with every panel delegate.
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }
}
