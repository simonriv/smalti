import SmaltiCore
import Testing

/// Spec F5.5, "Cuadrícula de `smalti img`": 12-cell thumbnails, as many columns as fit, name and size below.
@Suite("ImageGrid")
struct ImageGridTests {
    private let wide = CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16)

    private func image(_ name: String, _ width: Int = 1440, _ height: Int = 900) -> ImageDescription {
        ImageDescription(path: "/w/\(name)", name: name, pixelWidth: width, pixelHeight: height)
    }

    private func images(_ count: Int) -> [ImageDescription] {
        (1...count).map { image("img\($0).png") }
    }

    @Test func columnsFitWidth() {
        let grid = ImageGrid.layout(images(12), skipped: 0, in: wide)

        #expect(grid.columnsPerRow == 5)
        #expect(grid.rows.map(\.cells.count) == [5, 5, 2])
    }

    @Test func narrowTerminalGivesOneColumn() {
        let grid = ImageGrid.layout(images(3), skipped: 0, in: CellMetrics(columns: 10, cellWidth: 8, cellHeight: 16))

        #expect(grid.columnsPerRow == 1)
        #expect(grid.rows.map(\.cells.count) == [1, 1, 1])
    }

    @Test func exactWidthFitsWithoutTrailingGap() {
        let grid = ImageGrid.layout(images(3), skipped: 0, in: CellMetrics(columns: 26, cellWidth: 8, cellHeight: 16))

        #expect(grid.columnsPerRow == 2)
    }

    @Test func rowsFollowAspectAndCellRatio() throws {
        let cell = try #require(ImageGrid.layout([image("a.png")], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.rows == 4)  // 12 × 8 px wide → 60 px tall → 3.75 cells of 16 px
    }

    @Test func tallImageCapsAtSixRows() throws {
        let cell = try #require(
            ImageGrid.layout([image("a.png", 100, 1000)], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.rows == 6)
    }

    @Test func tinyImageHasAtLeastOneRow() throws {
        let cell = try #require(
            ImageGrid.layout([image("a.png", 1000, 10)], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.rows == 1)
    }

    @Test func rowHeightIsItsTallestCell() {
        let grid = ImageGrid.layout([image("a.png"), image("b.png", 100, 1000)], skipped: 0, in: wide)

        #expect(grid.rows.first?.height == 6)
    }

    @Test func orderIsNaturalCaseInsensitive() {
        let grid = ImageGrid.layout([image("img10.png"), image("Img2.png"), image("img1.png")], skipped: 0, in: wide)

        #expect(grid.rows.flatMap(\.cells).map(\.image.name) == ["img1.png", "Img2.png", "img10.png"])
    }

    @Test func labelsAreTruncatedToCellWidth() throws {
        let cell = try #require(
            ImageGrid.layout([image("landing-v3-final.png")], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.label == "landing-v3-…")
        #expect(cell.label.count == 12)
    }

    @Test func shortLabelIsKept() throws {
        let cell = try #require(ImageGrid.layout([image("hero.png")], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.label == "hero.png")
    }

    @Test func dimensionsAreWidthByHeight() throws {
        let cell = try #require(ImageGrid.layout([image("a.png")], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.dimensions == "1440×900")
    }

    @Test func summaryCountsSkipped() {
        #expect(
            ImageGrid.layout(images(12), skipped: 3, in: wide).summary == "12 imágenes · 3 omitidas (no son imagen)")
    }

    @Test func summaryOmitsSkippedWhenZero() {
        #expect(ImageGrid.layout(images(4), skipped: 0, in: wide).summary == "4 imágenes")
    }

    @Test func summaryIsSingular() {
        #expect(ImageGrid.layout(images(1), skipped: 1, in: wide).summary == "1 imagen · 1 omitida (no es imagen)")
    }

    @Test func overLimitAddsMore() {
        let grid = ImageGrid.layout(images(123), skipped: 0, in: wide)

        #expect(grid.rows.flatMap(\.cells).count == 100)
        #expect(grid.summary == "100 imágenes · … y 23 más (máximo 100)")
    }

    @Test func limitKeepsTheFirstInNaturalOrder() {
        let grid = ImageGrid.layout(images(101).reversed(), skipped: 0, in: wide)

        #expect(grid.rows.flatMap(\.cells).last?.image.name == "img100.png")
    }

    @Test(arguments: [0.0, -8, .infinity, .nan])
    func invalidCellWidthGivesOneRow(_ width: Double) throws {
        let metrics = CellMetrics(columns: 80, cellWidth: width, cellHeight: 16)

        let cell = try #require(ImageGrid.layout([image("a.png")], skipped: 0, in: metrics).rows.first?.cells.first)

        #expect(cell.rows == 1)
    }

    @Test(arguments: [0.0, .infinity, .nan])
    func invalidCellHeightGivesOneRow(_ height: Double) throws {
        let metrics = CellMetrics(columns: 80, cellWidth: 8, cellHeight: height)

        let cell = try #require(ImageGrid.layout([image("a.png")], skipped: 0, in: metrics).rows.first?.cells.first)

        #expect(cell.rows == 1)
    }

    @Test func absurdAspectCapsWithoutTrapping() throws {
        let cell = try #require(
            ImageGrid.layout([image("a.png", 1, Int.max)], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.rows == 6)
    }

    @Test(arguments: [0, -5])
    func noColumnsGiveOneColumn(_ columns: Int) {
        let grid = ImageGrid.layout(
            images(2), skipped: 0, in: CellMetrics(columns: columns, cellWidth: 8, cellHeight: 16))

        #expect(grid.columnsPerRow == 1)
    }

    @Test(arguments: [
        ("\u{1B}[2Jx.png", "?[2Jx.png"), ("a\nb.png", "a?b.png"), ("a\u{7F}.png", "a?.png"),
        ("a\u{9B}1m.png", "a?1m.png"),
    ])
    func controlCharactersInLabelsAreReplaced(_ name: String, _ label: String) throws {
        let cell = try #require(ImageGrid.layout([image(name)], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.label == label)
    }

    @Test func wideCharactersCountTwoCells() throws {
        let cell = try #require(
            ImageGrid.layout([image("写真写真写真写真.png")], skipped: 0, in: wide).rows.first?.cells.first)

        #expect(cell.label == "写真写真写…")
        #expect(TerminalText.width(cell.label) <= ImageGrid.cellColumns)
    }

    @Test func longDigitRunsSortByValue() {
        let small = "a" + String(repeating: "9", count: 20) + ".png"
        let big = "a1" + String(repeating: "0", count: 20) + ".png"

        let grid = ImageGrid.layout([image(big), image(small)], skipped: 0, in: wide)

        #expect(grid.rows.flatMap(\.cells).map(\.image.name) == [small, big])
    }

    private func order(_ names: [String]) -> [String] {
        ImageGrid.layout(names.map { image($0) }, skipped: 0, in: wide).rows.flatMap(\.cells).map(\.image.name)
    }

    @Test func caseIsIgnored() {
        #expect(order(["B.png", "a.png"]) == ["a.png", "B.png"])
    }

    @Test func sameNameInOtherCaseOrdersByText() {
        #expect(order(["img1.png", "IMG1.png"]) == ["IMG1.png", "img1.png"])
        #expect(order(["IMG1.png", "img1.png"]) == ["IMG1.png", "img1.png"])
    }

    @Test func shorterNameThatIsAPrefixComesFirst() {
        #expect(order(["photo2", "photo"]) == ["photo", "photo2"])
    }

    @Test func lettersDecideBeforeNumberLength() {
        #expect(order(["b1.png", "a10.png"]) == ["a10.png", "b1.png"])
    }

    @Test func numbersCompareByValueNotByDigits() {
        #expect(order(["img12.png", "img3.png"]) == ["img3.png", "img12.png"])
    }

    @Test func leadingZerosOrderBeforeSameValue() {
        #expect(order(["img1.png", "img01.png"]) == ["img01.png", "img1.png"])
    }

    @Test func numberChunkComesBeforeText() {
        #expect(order(["a.png", "1a.png"]) == ["1a.png", "a.png"])
        #expect(order(["1a.png", "a.png"]) == ["1a.png", "a.png"])
    }

    @Test func nonASCIIDigitsAreText() {
        #expect(order(["a²b.png", "a1b.png"]) == ["a1b.png", "a²b.png"])
    }

    /// Block 3 review m2: in a short pane the thumbnail leaves room for its name, its size and the prompt.
    @Test func shortPaneCapsTheThumbnailRows() throws {
        var metrics = CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16)
        metrics.visibleRows = 6

        let cell = try #require(
            ImageGrid.layout([image("a.png", 100, 1000)], skipped: 0, in: metrics).rows.first?.cells.first)

        #expect(cell.rows == 3)
    }

    @Test func tinyPaneStillGivesOneRow() throws {
        var metrics = CellMetrics(columns: 80, cellWidth: 8, cellHeight: 16)
        metrics.visibleRows = 2

        let cell = try #require(ImageGrid.layout([image("a.png")], skipped: 0, in: metrics).rows.first?.cells.first)

        #expect(cell.rows == 1)
    }

    @Test func noImagesGiveNoRows() {
        #expect(ImageGrid.layout([], skipped: 2, in: wide).rows.isEmpty)
    }
}
