/// Spec F5.5, "Miniatura al pasar el cursor": a word under the pointer becomes a card `delay` after the pointer
/// stops on it, from the first candidate path that is an image. A new word hides the card at once and cancels what
/// was loading; a load that finishes for a word the pointer already left is dropped.
@MainActor
public final class PreviewUnderPointer {
    public static let delay = Duration.milliseconds(300)

    public struct Ports {
        let files: any ImageFiles
        /// Waits `delay` (the app's) or until fired by hand (tests).
        let debouncer: any Debouncer
        /// F7.7: the card's words when an image cannot be shown.
        let texts: TerminalTexts

        public init(files: any ImageFiles, debouncer: any Debouncer, texts: TerminalTexts) {
            self.files = files
            self.debouncer = debouncer
            self.texts = texts
        }
    }

    public private(set) var current: PreviewCard?
    private let ports: Ports
    private let thumbnailSize: Size
    private let show: @MainActor (PreviewCard?) -> Void
    private var word: PointerWord?
    private var context: PreviewContext?
    private var load: Task<Void, Never>?

    public init(ports: Ports, thumbnailSize: Size, show: @escaping @MainActor (PreviewCard?) -> Void) {
        self.ports = ports
        self.thumbnailSize = thumbnailSize
        self.show = show
    }

    /// The pointer is over `word` (nil: over nothing, or out of the pane).
    public func pointerMoved(_ word: PointerWord?, context: PreviewContext) {
        guard word != self.word || context != self.context else { return }
        self.word = word
        self.context = context
        reset()
        guard let word else { return }
        ports.debouncer.schedule { [weak self] in self?.start(word, context: context) }
    }

    /// Waits for the load in flight, if any (the app never needs to; it is for callers that must know it ended).
    public func settle() async {
        await load?.value
    }

    private func reset() {
        ports.debouncer.cancel()
        load?.cancel()  // kept, cancelled, so `settle` still waits for it to wind down
        guard current != nil else { return }
        current = nil
        show(nil)
    }

    private func start(_ word: PointerWord, context: PreviewContext) {
        let paths = PreviewCandidates.paths(for: word.text, in: context)
        guard !paths.isEmpty else { return }
        let files = ports.files
        let size = thumbnailSize
        let texts = ports.texts
        load = Task { [weak self] in
            let card = await Self.card(for: paths, files: files, size: size, anchor: word.frame, texts: texts)
            guard !Task.isCancelled, let card, let self, self.word == word else { return }
            self.current = card
            self.show(card)
        }
    }

    /// The card of the first path that describes as an image; nil when none does.
    private nonisolated static func card(
        for paths: [String], files: any ImageFiles, size: Size, anchor: Rect, texts: TerminalTexts
    ) async -> PreviewCard? {
        for path in paths {
            guard !Task.isCancelled else { return nil }
            let image: ImageDescription
            do {
                image = try await files.describe(path)
            } catch .tooLarge {
                return .tooLarge(path: path, anchor: anchor, texts: texts)
            } catch {
                continue
            }
            // ImageIO cannot stop a decode once started: a load cancelled while describing never starts one.
            guard !Task.isCancelled else { return nil }
            do {
                return .image(image, thumbnail: try await files.thumbnail(of: path, fitting: size), anchor: anchor)
            } catch {
                return .unreadable(image, anchor: anchor, texts: texts)
            }
        }
        return nil
    }
}
