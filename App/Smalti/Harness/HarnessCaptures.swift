import Foundation
import SmaltiCore

/// Runs the capture of every pane whose foreground process becomes a harness, across all windows: it knows which
/// panes are still waiting (so two panes of the same harness and directory both fall back, review 1) and which ids
/// panes hold (so none takes another's). The ids come back through `apply`, onto the pane's binding (spec F6).
@MainActor
final class HarnessCaptures {
    private let capture: CaptureHarnessSession
    private var waiting: [PaneID: CaptureStart] = [:]
    private var held: [PaneID: String] = [:]

    init(registry: HarnessRegistry) {
        capture = CaptureHarnessSession(
            registry: registry, clock: { Date() }, sleep: { try? await Task.sleep(for: $0) },
            resolve: { URL(filePath: $0).resolvingSymlinksInPath().path(percentEncoded: false) })
    }

    /// `isStillRunning` says whether the pane still runs that process; `apply` puts the binding on the pane.
    func processChanged(
        in pane: Pane, to process: ForegroundProcess, isStillRunning: @escaping () -> Bool,
        apply: @escaping (HarnessBinding) -> Void
    ) {
        guard let start = capture.processChanged(in: pane, to: process) else { return }
        waiting[pane.id] = start
        apply(start.interimBinding)
        Task { [weak self] in
            guard let self else { return }
            let binding = await capture.capture(
                start, competitors: { self.competitors(of: start) }, claimed: { self.claimed(besides: start.pane) },
                isStillRunning: isStillRunning)
            finish(start, with: binding, apply: apply)
        }
    }

    func forget(_ pane: PaneID) {
        waiting[pane] = nil
        held[pane] = nil
    }

    private func finish(_ start: CaptureStart, with binding: HarnessBinding?, apply: (HarnessBinding) -> Void) {
        guard waiting[start.pane] == start else { return }
        waiting[start.pane] = nil
        guard let binding else { return }
        held[start.pane] = binding.sessionID
        apply(binding)
    }

    private func competitors(of start: CaptureStart) -> Int {
        waiting.values.filter {
            $0.pane != start.pane && $0.harness == start.harness && $0.decision == .search
                && ResolvedPath.same($0.directory, start.directory)
        }.count
    }

    private func claimed(besides pane: PaneID) -> Set<String> {
        Set(held.filter { $0.key != pane }.values)
    }
}
