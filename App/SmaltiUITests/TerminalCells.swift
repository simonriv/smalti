import XCTest

/// Clicks on a terminal's cells by their text (F6): needs `-SmaltiExposeCellSize YES`, which puts "celda 8 × 21" in
/// the terminal's title, and the Obsidiana padding (16 × 12 points).
extension XCUIElement {
    private static let terminalPadding = CGVector(dx: 16, dy: 12)

    /// The cell size the terminal reports; a terminal that does not report it fails the test instead of guessing.
    var cellSize: CGSize {
        let numbers = title.split(separator: " ").compactMap { Double($0) }
        guard numbers.count == 2 else {
            XCTFail("no cell size in the terminal's title: \(title)")
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: numbers[0], height: numbers[1])
    }

    /// ⌘-click on the last visible row starting with `text`, on its second character.
    func commandClick(onRowStartingWith text: String) {
        let rows = (value as? String ?? "").components(separatedBy: "\n")
        guard let row = rows.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(text) }) else {
            return XCTFail("no row starts with \(text)")
        }
        let cell = cellSize
        let offset = CGVector(
            dx: Self.terminalPadding.dx + 1.5 * cell.width,
            dy: Self.terminalPadding.dy + (Double(row) + 0.5) * cell.height)
        let point = coordinate(withNormalizedOffset: .zero).withOffset(offset)
        XCUIElement.perform(withKeyModifiers: .command) { point.click() }
    }
}
