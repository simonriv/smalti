import AppKit

/// A menu item that runs a closure: menus are built from `MenuModel`, not from selectors on a responder (F4.5).
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, keyEquivalent: String = "", run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runClosure), keyEquivalent: keyEquivalent)
        target = self
    }

    /// Built in code only; an archived item would have nothing to run.
    required init(coder: NSCoder) {
        run = {}
        super.init(coder: coder)
    }

    @objc private func runClosure() {
        run()
    }
}
