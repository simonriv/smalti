import AppKit
import SmaltiCore

/// Primary adapter for "Reportar un problema o una idea" (F4.5): the overlay keeps the chosen kind and whether to
/// save the logs; ↩ hands both to the app, which opens the issue. Nothing is sent from here.
@MainActor
final class FeedbackController {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private var view: FeedbackView?
    private var kind = FeedbackKind.bug
    private var includesLogs = false

    init(window: SmaltiWindow) {
        self.window = window
    }

    func open(theme: Theme, summary: String, submit: @escaping (FeedbackKind, Bool) -> Void) {
        guard !isOpen, let content = window.contentView else { return }
        kind = .bug
        includesLogs = false
        let view = FeedbackView(theme: theme, summary: summary)
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: theme.feedback.width),
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.feedback.topOffset),
        ])
        view.onKind = { [weak self] kind in
            self?.kind = kind
            self?.render()
        }
        view.onToggleLogs = { [weak self] in
            self?.includesLogs.toggle()
            self?.render()
        }
        view.onCancel = { [weak self] in self?.close() }
        view.onSubmit = { [weak self] in
            guard let self else { return }
            let (kind, logs) = (self.kind, includesLogs)
            close()
            submit(kind, logs)
        }
        self.view = view
        isOpen = true
        render()
        window.makeFirstResponder(view)
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        view?.removeFromSuperview()
        view = nil
        isOpen = false
        onOpenChange?(false)
    }

    private func render() {
        view?.show(kind: kind, includesLogs: includesLogs)
    }
}
