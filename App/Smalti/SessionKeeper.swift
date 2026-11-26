import Foundation
import OSLog
import SmaltiCore

/// Saves the windows as they change (spec F2; every window since F4.5): the structure one second after the last change, the scrollback every
/// five minutes and on quit. A failed save is logged and reported once through `onFailure`; it never blocks.
@MainActor
final class SessionKeeper {
    static let structureDelay: Duration = .seconds(1)
    static let scrollbackInterval: Duration = .seconds(5 * 60)

    var onFailure: ((String) -> Void)?
    /// F6: each Smalti Neovim's file and line, asked right before every save.
    var editorPositions: @MainActor () async -> [PaneID: EditorPosition] = { [:] }

    private let save: SaveSession
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "session")
    private var pendingStructure: Task<Void, Never>?
    private var periodicScrollback: Task<Void, Never>?
    private var latest: WindowSet?
    private var lastFailure: String?
    /// After "Empezar limpio", the last session stays on disk until the user changes something on purpose.
    private var heldStructure: [[String]]?

    init(save: SaveSession) {
        self.save = save
    }

    /// Starts the periodic scrollback save; until then nothing is saved (e.g. while the resume screen shows).
    func start(with set: WindowSet) {
        latest = set
        periodicScrollback = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.scrollbackInterval)
                guard !Task.isCancelled, let self, self.latest != nil else { return }
                if self.heldStructure != nil { continue }
                let editors = await self.editorPositions()
                // Quit may have saved, or "Empezar limpio" started a hold, while Neovim answered.
                guard !Task.isCancelled, self.heldStructure == nil, let set = self.latest else { continue }
                self.report(self.save.saveWithScrollback(of: set, at: .now, editors: editors))
            }
        }
    }

    /// Starts like `start(with:)`, but keeps the previous session (also at quit) until the structure changes.
    func startKeepingPreviousSession(with set: WindowSet) {
        heldStructure = set.structure
        start(with: set)
    }

    func changed(_ set: WindowSet) {
        guard periodicScrollback != nil else { return }
        if let held = heldStructure {
            guard set.structure != held else { return }
            heldStructure = nil
        }
        latest = set
        pendingStructure?.cancel()
        pendingStructure = Task { [weak self] in
            try? await Task.sleep(for: Self.structureDelay)
            guard !Task.isCancelled, let self else { return }
            let editors = await self.editorPositions()
            guard !Task.isCancelled, let set = self.latest else { return }
            self.report(self.save.saveStructure(of: set, at: .now, editors: editors))
        }
    }

    /// On quit: everything, now.
    func saveForQuit() async {
        pendingStructure?.cancel()
        periodicScrollback?.cancel()
        guard heldStructure == nil, latest != nil else { return }
        let editors = await editorPositions()
        guard let set = latest else { return }
        report(save.saveWithScrollback(of: set, at: .now, editors: editors))
    }

    private func report(_ outcome: SaveOutcome) {
        guard case .failed(let error) = outcome else {
            lastFailure = nil
            return
        }
        let reason = error.summary(.spanish /* T9 */)
        logger.error("could not save the session: \(reason, privacy: .public)")
        guard reason != lastFailure else { return }
        lastFailure = reason
        onFailure?(reason)
    }
}
