import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5.5: the card shows the first image a hovered word names, 300 ms after the pointer stops on it, and never
/// a card for a word the pointer already left.
@MainActor
@Suite("PreviewUnderPointer")
struct PreviewUnderPointerTests {
    private let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls shots")
    private let frame = Rect(x: 10, y: 20, width: 80, height: 16)
    private let debouncer = ManualDebouncer()
    private let shown = Shown()

    private func preview(_ files: InMemoryImageFiles) -> PreviewUnderPointer {
        PreviewUnderPointer(
            ports: PreviewUnderPointer.Ports(files: files, debouncer: debouncer),
            thumbnailSize: Size(width: 388, height: 208), show: { [shown] in shown.cards.append($0) })
    }

    private func word(_ text: String, x: Double = 10) -> PointerWord {
        PointerWord(text: text, frame: Rect(x: x, y: 20, width: 80, height: 16))
    }

    @Test func cardAppearsOnlyAfterDebounce() async {
        let preview = preview(InMemoryImageFiles(["/w/a.png": .image(width: 1440, height: 900)]))

        preview.pointerMoved(word("a.png"), context: context)
        #expect(shown.cards.isEmpty)
        debouncer.fire()
        await preview.settle()

        #expect(
            shown.cards == [
                PreviewCard.image(
                    ImageDescription(path: "/w/a.png", name: "a.png", pixelWidth: 1440, pixelHeight: 900),
                    thumbnail: InMemoryImageFiles.thumbnailData(for: "/w/a.png"), anchor: frame)
            ])
        #expect(preview.current?.path == "/w/a.png")
    }

    @Test func firstExistingCandidateWins() async {
        let files = InMemoryImageFiles([
            "/w/shots/a.png": .image(width: 10, height: 10), "/w/a.png": .image(width: 20, height: 20),
        ])
        let preview = preview(files)

        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(preview.current?.path == "/w/shots/a.png")
    }

    @Test func missingFileGivesNoCard() async {
        let preview = preview(InMemoryImageFiles([:]))

        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(shown.cards.isEmpty)
        #expect(preview.current == nil)
    }

    @Test func nonImageWordNeverTouchesTheDisk() async {
        let files = InMemoryImageFiles([:])
        let preview = preview(files)

        preview.pointerMoved(word("notes.md"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(files.described.isEmpty)
    }

    @Test func nilWordHidesCard() async {
        let preview = preview(InMemoryImageFiles(["/w/a.png": .image(width: 1, height: 1)]))
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        preview.pointerMoved(nil, context: context)

        #expect(shown.cards.last == .some(nil))
        #expect(preview.current == nil)
    }

    @Test func otherWordHidesCardAtOnce() async {
        let preview = preview(InMemoryImageFiles(["/w/a.png": .image(width: 1, height: 1)]))
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        preview.pointerMoved(word("b.png", x: 200), context: context)

        #expect(shown.cards.last == .some(nil))
    }

    @Test func staleThumbnailIsDropped() async {
        let files = InMemoryImageFiles([
            "/w/a.png": .image(width: 1, height: 1), "/w/b.png": .image(width: 2, height: 2),
        ])
        files.hold("/w/a.png")
        let preview = preview(files)
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()

        preview.pointerMoved(word("b.png", x: 200), context: context)
        files.release("/w/a.png")
        debouncer.fire()
        await preview.settle()

        #expect(shown.cards.compactMap { $0?.path } == ["/w/b.png"])
    }

    @Test func changingWordCancelsPendingLoad() async {
        let files = InMemoryImageFiles(["/w/a.png": .image(width: 1, height: 1)])
        files.hold("/w/a.png")
        let preview = preview(files)
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await files.waitUntilRequested("/w/a.png")

        preview.pointerMoved(nil, context: context)
        files.release("/w/a.png")
        await preview.settle()

        #expect(files.cancelled == ["/w/a.png"])
    }

    @Test func leavingBeforeDebounceCancelsIt() async {
        let files = InMemoryImageFiles(["/w/a.png": .image(width: 1, height: 1)])
        let preview = preview(files)
        preview.pointerMoved(word("a.png"), context: context)

        preview.pointerMoved(nil, context: context)
        debouncer.fire()
        await preview.settle()

        #expect(files.described.isEmpty)
        #expect(shown.cards.isEmpty)
    }

    @Test func thumbnailFailureShowsReadError() async {
        let preview = preview(InMemoryImageFiles(["/w/a.png": .broken(width: 4, height: 3)]))

        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(preview.current?.caption(shortcut: "⌘Y") == "a.png · No se pudo leer la imagen")
        #expect(preview.current?.thumbnail == nil)
    }

    @Test func tooLargeShowsTooLarge() async {
        let preview = preview(InMemoryImageFiles(["/w/shots/a.png": .tooLarge]))

        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(preview.current?.caption(shortcut: "⌘Y") == "a.png · Imagen demasiado grande")
        #expect(preview.current?.path == "/w/shots/a.png")
    }

    @Test(arguments: [InMemoryImageFiles.Entry.text, .unreadable])
    func undescribableFileShowsNothing(_ entry: InMemoryImageFiles.Entry) async {
        let preview = preview(InMemoryImageFiles(["/w/a.png": entry]))

        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(shown.cards.isEmpty)
    }

    /// Block 2 review I1: a load cancelled while describing never starts the (uncancellable) thumbnail.
    @Test func cancelledLoadNeverStartsThumbnail() async {
        let files = InMemoryImageFiles(["/w/a.png": .image(width: 1, height: 1)])
        files.hold("/w/a.png", at: .describe)
        let preview = preview(files)
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await files.waitUntilRequested("/w/a.png", at: .describe)

        preview.pointerMoved(nil, context: context)
        files.release("/w/a.png")
        await preview.settle()

        #expect(files.thumbnailed.isEmpty)
    }

    /// Block 2 review m4: after `cd` or another command the same word may name another file.
    @Test func sameWordInOtherContextReloads() async {
        let files = InMemoryImageFiles([
            "/w/a.png": .image(width: 1, height: 1), "/x/a.png": .image(width: 2, height: 2),
        ])
        let preview = preview(files)
        preview.pointerMoved(
            word("a.png"), context: PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: nil))
        debouncer.fire()
        await preview.settle()

        preview.pointerMoved(
            word("a.png"), context: PreviewContext(workingDirectory: "/x", home: "/h", lastCommand: nil))
        debouncer.fire()
        await preview.settle()

        #expect(preview.current?.path == "/x/a.png")
    }

    @Test func goingBackToAWordShowsItOnce() async {
        let files = InMemoryImageFiles([
            "/w/a.png": .image(width: 1, height: 1), "/w/b.png": .image(width: 1, height: 1),
        ])
        files.hold("/w/a.png")
        let preview = preview(files)
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await files.waitUntilRequested("/w/a.png")

        preview.pointerMoved(word("b.png", x: 200), context: context)
        preview.pointerMoved(word("a.png"), context: context)
        files.release("/w/a.png")
        debouncer.fire()
        await preview.settle()

        #expect(shown.cards.compactMap { $0?.path } == ["/w/a.png"])
    }

    @Test func sameWordDoesNotReload() async {
        let files = InMemoryImageFiles(["/w/a.png": .image(width: 1, height: 1)])
        let preview = preview(files)
        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        preview.pointerMoved(word("a.png"), context: context)
        debouncer.fire()
        await preview.settle()

        #expect(files.described == ["/w/shots/a.png", "/w/a.png"])
        #expect(shown.cards.count == 1)
    }
}

@MainActor
final class Shown {
    var cards: [PreviewCard?] = []
}

@Suite("ImageFiles contract")
struct InMemoryImageFilesContractTests {
    @Test func inMemoryFulfillsTheContract() async throws {
        try await ImageFilesContract.verify {
            ImageFilesSample(
                files: InMemoryImageFiles(["/w/landing-v3.png": .image(width: 1440, height: 900), "/w/n.txt": .text]),
                image: "/w/landing-v3.png", text: "/w/n.txt", missing: "/w/none.png")
        }
    }
}
