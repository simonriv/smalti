/// Where a `line`'s answers go: `send` writes one to the shell; `isLatest` says whether a `seq` is still the shell's
/// last line, so a late follow-up never repaints a newer one.
@MainActor
public struct LineChannel {
    public let send: (SmaltiMessage) -> Void
    public let isLatest: (Int) -> Bool

    public init(send: @escaping (SmaltiMessage) -> Void, isLatest: @escaping (Int) -> Bool) {
        self.send = send
        self.isLatest = isLatest
    }
}

/// F5.6: answers a `line` with its ghost and its highlight, each sent as soon as it is ready: the ghost never waits
/// for the highlight (spec, "Resaltado: flujo por tecla", step 2), and `answer` returns once the ghost is out. The follow-up of an incomplete highlight (a spec
/// that loads, a slow path) runs on its own, so the next line is never held up by it.
@MainActor
public struct LineAnswers {
    private let session: InputSession
    private let highlighter: HighlightLine?

    public init(session: InputSession, highlighter: HighlightLine?) {
        self.session = session
        self.highlighter = highlighter
    }

    public func answer(_ request: HighlightRequest, pane: PaneID, channel: LineChannel) async {
        let session = session
        let ghost = Task { @MainActor in
            let text = await session.suggest(request.line, pane: pane, directory: request.directory)
            channel.send(.suggest(seq: request.seq, text))
        }
        // The highlight goes out on its own: the caller's message loop only waits for the ghost (final review, I1).
        if let highlighter {
            Task { @MainActor in await Self.highlight(request, using: highlighter, channel: channel) }
        }
        await ghost.value
    }

    private static func highlight(_ request: HighlightRequest, using highlighter: HighlightLine, channel: LineChannel)
        async
    {
        let answer = await InputRouting.highlight(request, using: highlighter)
        channel.send(answer.first)
        guard answer.needsFollowUp else { return }
        Task { @MainActor in
            let followUp = await InputRouting.followUp(request, using: highlighter)
            if channel.isLatest(request.seq) { channel.send(followUp) }
        }
    }
}
