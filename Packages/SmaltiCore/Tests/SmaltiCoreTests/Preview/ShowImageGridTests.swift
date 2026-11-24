import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5.5, "Cuadrícula de `smalti img`": the text written to the terminal, row by row as each is ready, or a plain
/// list when the output is not a terminal.
@Suite("ShowImageGrid")
struct ShowImageGridTests {
    final class RecordingSink: GridSink, @unchecked Sendable {
        let metrics: CellMetrics?
        private(set) var writes: [String] = []
        var text: String { writes.joined() }

        init(metrics: CellMetrics?) {
            self.metrics = metrics
        }

        func write(_ text: String) { writes.append(text) }
    }

    private let metrics = CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16)
    private let escape = "\u{1B}"

    private func files(_ names: [String], size: (Int, Int) = (1440, 900)) -> InMemoryImageFiles {
        InMemoryImageFiles(
            Dictionary(uniqueKeysWithValues: names.map { ("/w/\($0)", .image(width: size.0, height: size.1)) }))
    }

    private func listing(_ names: [String], skipped: Int = 0) -> ImageListing {
        ImageListing(source: "shots", images: names.map { "/w/\($0)" }, skipped: skipped)
    }

    private func render(_ listing: ImageListing, terminal: Bool = true, files: InMemoryImageFiles) async
        -> RecordingSink
    {
        let sink = RecordingSink(metrics: terminal ? metrics : nil)
        await ShowImageGrid.render(listing, to: sink, files: files)
        return sink
    }

    @Test func oneImageGolden() async {
        let sink = await render(listing(["a.png"]), files: files(["a.png"]))

        let png = InMemoryImageFiles.thumbnailData(for: "/w/a.png").base64EncodedString()
        #expect(
            sink.text
                == "\n\n\n\n\(escape)[4A\(escape)_Ga=T,f=100,q=2,C=1,c=12,m=0;\(png)\(escape)\\\(escape)[14C"
                + "\r\(escape)[4B\(escape)[2ma.png\(escape)[0m\n\(escape)[2m1440×900\(escape)[0m\n1 imagen\n")
    }

    /// Final review m3: each row is written as soon as its thumbnails are ready, the summary last.
    @Test func rowsAreWrittenOneByOne() async {
        let names = (1...7).map { "img\($0).png" }

        let sink = await render(listing(names), files: files(names))

        #expect(sink.writes.count == 3)
        #expect(sink.writes.last == "7 imágenes\n")
    }

    @Test func fourImagesShareOneRow() async {
        let names = ["a.png", "b.png", "c.png", "d.png"]

        let text = await render(listing(names), files: files(names)).text

        #expect(text.components(separatedBy: "\(escape)_Ga=T").count - 1 == 4)
        #expect(text.components(separatedBy: "\(escape)[4A").count - 1 == 1)
        #expect(text.hasSuffix("4 imágenes\n"))
    }

    @Test func tallImageIsSentByRows() async {
        let text = await render(listing(["a.png"]), files: files(["a.png"], size: (1000, 2000))).text

        #expect(text.contains("\(escape)_Ga=T,f=100,q=2,C=1,r=6,m=0;"))
    }

    @Test func labelsArePaddedToTheirColumns() async {
        let names = ["a.png", "landing-v3-final.png"]

        let text = await render(listing(names), files: files(names)).text

        #expect(text.contains("\(escape)[2ma.png         landing-v3-…\(escape)[0m\n"))
        #expect(text.contains("\(escape)[2m1440×900      1440×900\(escape)[0m\n"))
    }

    @Test func hundredOneImagesDrawTheLimit() async {
        let names = (1...101).map { "img\($0).png" }

        let text = await render(listing(names), files: files(names)).text

        #expect(text.components(separatedBy: "\(escape)_Ga=T").count - 1 == 100)
        #expect(text.hasSuffix("100 imágenes · … y 1 más (máximo 100)\n"))
    }

    @Test func pipedOutputHasNoEscape() async {
        let names = ["b.png", "a\u{1B}[2J.png"]

        let text = await render(listing(names, skipped: 2), terminal: false, files: files(names)).text

        #expect(!text.contains(escape))
        #expect(text == "a?[2J.png  1440×900\nb.png  1440×900\n2 imágenes · 2 omitidas (no son imagen)\n")
    }

    @Test func undescribableImagesCountAsSkipped() async {
        let files = InMemoryImageFiles(["/w/a.png": .image(width: 10, height: 10), "/w/b.png": .text])

        let text = await render(listing(["a.png", "b.png"]), terminal: false, files: files).text

        #expect(text.hasSuffix("1 imagen · 1 omitida (no es imagen)\n"))
    }

    @Test func undecodableThumbnailCountsAsSkipped() async {
        let files = InMemoryImageFiles([
            "/w/a.png": .image(width: 10, height: 10), "/w/b.png": .broken(width: 4, height: 4),
        ])

        let text = await render(listing(["a.png", "b.png"]), files: files).text

        #expect(text.components(separatedBy: "\(escape)_Ga=T").count - 1 == 1)
        #expect(!text.contains("b.png"))
        #expect(text.hasSuffix("1 imagen · 1 omitida (no es imagen)\n"))
    }

    @Test func thumbnailsFitTheirCells() async {
        let files = files(["a.png"])

        _ = await render(listing(["a.png"]), files: files)

        #expect(files.thumbnailSizes == [Size(width: 96, height: 64)])
    }

    @Test func emptyFolderSaysNoImages() async {
        let text = await render(listing([], skipped: 3), files: files([])).text

        #expect(text == "Sin imágenes en shots\n")
    }
}
