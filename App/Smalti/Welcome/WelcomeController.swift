import AppKit
import SmaltiCore

/// What the welcome card asks of the app: the integrations' states, installing one, painting a theme, and marking
/// the card seen.
@MainActor
struct WelcomeActions {
    let states: () -> [IntegrationID: IntegrationState]
    let install: (IntegrationID) -> Void
    let selectTheme: (ThemeID) -> Void
    let markDone: () -> Void
}

/// Primary adapter for the welcome card (spec F7.7): keeps its `WelcomeState`, runs the integrations' installs with
/// the palette's own commands and paints the theme live; ↩ keeps the theme, esc puts the original back, both mark it.
@MainActor
final class WelcomeController {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private var view: WelcomeView?
    private var state: WelcomeState?
    private var actions: WelcomeActions?
    private var installing = Set<WelcomeRow>()
    private var refresh: Timer?
    private var stateObserver: NSObjectProtocol?

    /// While an install runs, the states are read again this often until they change (or the limit passes).
    private static let refreshInterval: TimeInterval = 0.5
    private static let refreshLimit = 40

    init(window: SmaltiWindow) {
        self.window = window
    }

    func open(theme: Theme, keymap: Keymap, currentTheme: ThemeID, actions: WelcomeActions) {
        guard !isOpen, let content = window.contentView else { return }
        let states = actions.states()
        state = WelcomeState(
            claude: states[.claudePlugin] ?? .unknown, neovim: states[.claudecodeNvim] ?? .unknown,
            theme: currentTheme)
        self.actions = actions
        let view = WelcomeView(theme: theme, texts: .current, keymap: keymap)
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: theme.welcome.width),
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor, constant: theme.welcome.topOffset),
        ])
        wire(view)
        self.view = view
        isOpen = true
        // The integrations are checked in the background at launch: the card follows their states as they arrive.
        stateObserver = NotificationCenter.default.addObserver(
            forName: .claudeIntegrationChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.followStates() } }
        render()
        window.makeFirstResponder(view)
        fadeIn(view, duration: theme.observatory.fadeDuration)
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        refresh?.invalidate()
        refresh = nil
        stateObserver.map(NotificationCenter.default.removeObserver)
        stateObserver = nil
        view?.removeFromSuperview()
        view = nil
        state = nil
        installing = []
        isOpen = false
        onOpenChange?(false)
    }

    private func wire(_ view: WelcomeView) {
        view.onMove = { [weak self] step in self?.update { $0.move(step) } }
        view.onChoose = { [weak self] row in
            self?.update { state in
                let rows = WelcomeRow.allCases
                state.move((rows.firstIndex(of: row) ?? 0) - (rows.firstIndex(of: state.selected) ?? 0))
            }
        }
        view.onCycleTheme = { [weak self] step in self?.cycleTheme(step) }
        view.onInstall = { [weak self] in self?.install() }
        view.onFinish = { [weak self] in self?.end { $0.finish() } }
        view.onSkip = { [weak self] in self?.end { $0.skip() } }
    }

    private func update(_ change: (inout WelcomeState) -> Void) {
        guard var current = state else { return }
        change(&current)
        state = current
        render()
    }

    private func cycleTheme(_ step: Int) {
        guard state?.selected == .theme else { return }
        update { $0.cycleTheme(step) }
        if let theme = state?.theme { actions?.selectTheme(theme) }
    }

    private func install() {
        guard let state, state.canInstall(state.selected), !installing.contains(state.selected),
            let id = Self.integration(state.selected)
        else { return }
        installing.insert(state.selected)
        render()
        actions?.install(id)
        watchStates(remaining: Self.refreshLimit)
    }

    /// Reads the integrations again until no install is pending (each one changes its state when done).
    private func watchStates(remaining: Int) {
        refresh?.invalidate()
        refresh = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reread(remaining: remaining) }
        }
    }

    private func reread(remaining: Int) {
        guard let actions, var current = state else { return }
        let states = actions.states()
        for row in installing {
            guard let id = Self.integration(row), let now = states[id], now != current.integration(row) else {
                continue
            }
            if row == .claude { current.claude = now } else { current.neovim = now }
            installing.remove(row)
        }
        state = current
        render()
        if !installing.isEmpty, remaining > 0 { watchStates(remaining: remaining - 1) } else { installing = [] }
    }

    /// A state that changed outside an install (the launch check): taken as it is.
    private func followStates() {
        guard let actions, var current = state else { return }
        let states = actions.states()
        if !installing.contains(.claude), let claude = states[.claudePlugin] { current.claude = claude }
        if !installing.contains(.neovim), let neovim = states[.claudecodeNvim] { current.neovim = neovim }
        state = current
        render()
    }

    private func end(_ outcome: (WelcomeState) -> WelcomeOutcome) {
        guard let state, let actions else { return }
        let result = outcome(state)
        if let theme = result.theme { actions.selectTheme(theme) }
        if result.marksDone { actions.markDone() }
        close()
    }

    /// The overlays' fade (at most 150 ms); none with "Reducir movimiento".
    private func fadeIn(_ view: NSView, duration: Double) {
        guard !Motion.isReduced, duration > 0 else { return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            view.animator().alphaValue = 1
        }
    }

    private func render() {
        guard let state else { return }
        view?.show(state, installing: installing)
    }

    private static func integration(_ row: WelcomeRow) -> IntegrationID? {
        switch row {
        case .claude: .claudePlugin
        case .neovim: .claudecodeNvim
        case .theme: nil
        }
    }
}
