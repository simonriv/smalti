import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5.5, "Cuadrícula de `smalti img`": the text written to the terminal, or a plain list when it is not one.
@Suite("ShowImageGrid")
struct ShowImageGridTests {
    private let metrics = CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16)
    private let escape = "\u{1B}"

    private func files(_ names: [String], size: (Int, Int) = (1440, 900)) -> InMemoryImageFiles {
        InMemoryImageFiles(
            Dictionary(uniqueKeysWithValues: names.map { ("/w/\($0)", .image(width: size.0, height: size.1)) }))
    }

    private func listing(_ names: [String], skipped: Int = 0) -> ImageListing {
        ImageListing(source: "shots", images: names.map { "/w/\($0)" }, skipped: skipped)
    }

    @Test func oneImageGolden() async {
        let output = await ShowImageGrid.render(listing(["a.png"]), metrics: metrics, files: files(["a.png"]))

        let png = InMemoryImageFiles.thumbnailData(for: "/w/a.png").base64EncodedString()
        #expect(
            output.stdout
                == "\n\n\n\n\(escape)[4A\(escape)_Ga=T,f=100,q=2,C=1,c=12,r=4,m=0;\(png)\(escape)\\\(escape)[14C"
                + "\r\(escape)[4B\(escape)[2ma.png\(escape)[0m\n\(escape)[2m1440×900\(escape)[0m\n1 imagen\n")
        #expect(output.exitCode == 0)
        #expect(output.stderr.isEmpty)
    }

    @Test func fourImagesShareOneRow() async {
        let names = ["a.png", "b.png", "c.png", "d.png"]

        let output = await ShowImageGrid.render(listing(names), metrics: metrics, files: files(names))

        #expect(output.stdout.components(separatedBy: "\(escape)_Ga=T").count - 1 == 4)
        #expect(output.stdout.components(separatedBy: "\(escape)[4A").count - 1 == 1)
        #expect(output.stdout.hasSuffix("4 imágenes\n"))
    }

    @Test func labelsArePaddedToTheirColumns() async {
        let names = ["a.png", "landing-v3-final.png"]

        let output = await ShowImageGrid.render(listing(names), metrics: metrics, files: files(names))

        #expect(output.stdout.contains("\(escape)[2ma.png         landing-v3-…\(escape)[0m\n"))
        #expect(output.stdout.contains("\(escape)[2m1440×900      1440×900\(escape)[0m\n"))
    }

    @Test func hundredOneImagesDrawTheLimit() async {
        let names = (1...101).map { "img\($0).png" }

        let output = await ShowImageGrid.render(listing(names), metrics: metrics, files: files(names))

        #expect(output.stdout.components(separatedBy: "\(escape)_Ga=T").count - 1 == 100)
        #expect(output.stdout.hasSuffix("100 imágenes · … y 1 más (máximo 100)\n"))
    }

    @Test func pipedOutputHasNoEscape() async {
        let names = ["b.png", "a\u{1B}[2J.png"]

        let output = await ShowImageGrid.render(listing(names, skipped: 2), metrics: nil, files: files(names))

        #expect(!output.stdout.contains(escape))
        #expect(output.stdout == "a?[2J.png  1440×900\nb.png  1440×900\n2 imágenes · 2 omitidas (no son imagen)\n")
    }

    @Test func undescribableImagesCountAsSkipped() async {
        let files = InMemoryImageFiles(["/w/a.png": .image(width: 10, height: 10), "/w/b.png": .text])

        let output = await ShowImageGrid.render(listing(["a.png", "b.png"]), metrics: nil, files: files)

        #expect(output.stdout.hasSuffix("1 imagen · 1 omitida (no es imagen)\n"))
    }

    @Test func undecodableThumbnailCountsAsSkipped() async {
        let files = InMemoryImageFiles([
            "/w/a.png": .image(width: 10, height: 10), "/w/b.png": .broken(width: 4, height: 4),
        ])

        let output = await ShowImageGrid.render(listing(["a.png", "b.png"]), metrics: metrics, files: files)

        #expect(output.stdout.components(separatedBy: "\(escape)_Ga=T").count - 1 == 1)
        #expect(output.stdout.hasSuffix("1 imagen · 1 omitida (no es imagen)\n"))
    }

    @Test func thumbnailsFitTheirCells() async {
        let files = files(["a.png"])

        _ = await ShowImageGrid.render(listing(["a.png"]), metrics: metrics, files: files)

        #expect(files.thumbnailSizes == [Size(width: 96, height: 64)])
    }

    @Test func emptyFolderSaysNoImages() async {
        let output = await ShowImageGrid.render(listing([], skipped: 3), metrics: metrics, files: files([]))

        #expect(output.stdout == "Sin imágenes en shots\n")
        #expect(output.exitCode == 0)
    }
}
