import Foundation

/// F9's panel: reads the focused pane's session, keeps it up to date while shown and lets go of everything when
/// closed (no reads, watchers or timeline in memory: spec C6).
@MainActor
public final class ShowTimeline {
    public struct TimelineSession: Equatable, Sendable {
        public let ref: TranscriptSessionRef
        public let timeline: Timeline
        /// The latest session of the folder standing in for one Smalti could not name.
        public let isUnidentified: Bool
    }

    public enum State: Equatable, Sendable {
        case closed
        case loading
        case session(TimelineSession)
        case empty(recent: [HarnessSession])
        case unreadable(HarnessID, recent: [HarnessSession])
        case failed(TranscriptReadError)
    }

    /// Sessions listed by the empty and fallback states.
    public static let recentLimit = 6

    private let sources: TranscriptSources
    public private(set) var state = State.closed
    public var onChange: (() -> Void)?
    private var watch: Task<Void, Never>?
    private var generation = 0

    public init(sources: TranscriptSources) {
        self.sources = sources
    }

    public var isWatching: Bool { watch != nil }

    public func show(_ resolution: TimelineTarget.Resolution, root: String) async {
        let current = restart()
        switch resolution {
        case .session(let harness, let id): await open(harness, id, unidentified: false, current)
        case .unidentified(let harness, let directory):
            let latest = try? await sources.project(harness)?.sessions(under: directory, limit: 1).first
            guard isCurrent(current) else { return }
            guard let latest else { return set(.empty(recent: await recent(root, current) ?? []), current) }
            await open(harness, latest.id, unidentified: true, current)
        case .unreadable(let harness):
            guard let recent = await recent(root, current) else { return }
            set(.unreadable(harness, recent: recent), current)
        case .noAgent:
            guard let recent = await recent(root, current) else { return }
            set(.empty(recent: recent), current)
        }
    }

    /// A session chosen from the recent list or a search result.
    public func open(_ session: HarnessSession) async {
        await open(session.harness, session.id, unidentified: false, restart())
    }

    public func close() {
        _ = restart()
        state = .closed
        onChange?()
    }

    private func restart() -> Int {
        generation += 1
        watch?.cancel()
        watch = nil
        state = .loading
        return generation
    }

    private func isCurrent(_ current: Int) -> Bool { current == generation }

    private func set(_ new: State, _ current: Int) {
        guard isCurrent(current) else { return }
        state = new
        onChange?()
    }

    private func recent(_ root: String, _ current: Int) async -> [HarnessSession]? {
        let recent = await sources.recent(under: root, limit: Self.recentLimit)
        return isCurrent(current) ? recent : nil
    }

    private func open(_ harness: HarnessID, _ id: String, unidentified: Bool, _ current: Int) async {
        guard let transcripts = sources.session(harness) else { return set(.unreadable(harness, recent: []), current) }
        do {
            let ref = try await transcripts.locate(sessionID: id)
            let read = try await transcripts.read(ref, from: .start)
            guard isCurrent(current) else { return }
            let session = TimelineSession(
                ref: ref, timeline: Timeline().appending(read.entries), isUnidentified: unidentified)
            set(.session(session), current)
            follow(session, from: read.cursor, with: transcripts, current)
        } catch {
            set(.failed(error), current)
        }
    }

    private func follow(
        _ session: TimelineSession, from cursor: TranscriptCursor, with transcripts: any SessionTranscripts,
        _ current: Int
    ) {
        watch = Task { [weak self] in
            var cursor = cursor
            var timeline = session.timeline
            for await _ in transcripts.changes(of: session.ref) {
                guard let read = try? await transcripts.read(session.ref, from: cursor), !Task.isCancelled else {
                    continue
                }
                cursor = read.cursor
                timeline = (read.restarted ? Timeline() : timeline).appending(read.entries)
                self?.set(
                    .session(
                        TimelineSession(ref: session.ref, timeline: timeline, isUnidentified: session.isUnidentified)),
                    current)
            }
        }
    }
}
