import Foundation
import OSLog
import SmaltiCore

/// Saves the window as it changes (spec F2): the structure one second after the last change, the scrollback every
/// five minutes and on quit. A failed save is logged and reported once through `onFailure`; it never blocks.
@MainActor
final class SessionKeeper {
    static let structureDelay: Duration = .seconds(1)
    static let scrollbackInterval: Duration = .seconds(5 * 60)

    var onFailure: ((String) -> Void)?

    private let save: SaveSession
    private let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "session")
    private var pendingStructure: Task<Void, Never>?
    private var periodicScrollback: Task<Void, Never>?
    private var latest: WorkspaceSet?
    private var lastFailure: String?

    init(save: SaveSession) {
        self.save = save
    }

    /// Starts the periodic scrollback save; until then nothing is saved (e.g. while the resume screen shows).
    func start(with set: WorkspaceSet) {
        latest = set
        periodicScrollback = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.scrollbackInterval)
                guard !Task.isCancelled, let self, let set = self.latest else { return }
                self.report(self.save.saveWithScrollback(of: set, at: .now))
            }
        }
    }

    func changed(_ set: WorkspaceSet) {
        guard periodicScrollback != nil else { return }
        latest = set
        pendingStructure?.cancel()
        pendingStructure = Task { [weak self] in
            try? await Task.sleep(for: Self.structureDelay)
            guard !Task.isCancelled, let self, let set = self.latest else { return }
            self.report(self.save.saveStructure(of: set, at: .now))
        }
    }

    /// On quit: everything, now.
    func saveForQuit() {
        pendingStructure?.cancel()
        periodicScrollback?.cancel()
        guard let set = latest else { return }
        report(save.saveWithScrollback(of: set, at: .now))
    }

    private func report(_ outcome: SaveOutcome) {
        guard case .failed(let reason) = outcome else {
            lastFailure = nil
            return
        }
        logger.error("could not save the session: \(reason, privacy: .public)")
        guard reason != lastFailure else { return }
        lastFailure = reason
        onFailure?(reason)
    }
}
