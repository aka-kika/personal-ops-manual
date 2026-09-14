import XCTest
@testable import OpsManual

final class TableLayoutTests: XCTestCase {
    func testShortCellsAreClampedToTheMinimumWidth() {
        let widths = TableLayout.columnWidths(header: ["A"], rows: [["b"], ["c"]])
        XCTAssertEqual(widths.count, 1)
        XCTAssertEqual(widths[0], TableLayout.minColumnWidth)
    }

    func testVeryLongCellsAreClampedToTheMaximumWidth() {
        let long = String(repeating: "wide text that keeps going ", count: 20)
        let widths = TableLayout.columnWidths(header: ["Role"], rows: [[long]])
        XCTAssertEqual(widths[0], TableLayout.maxColumnWidth)
    }

    func testLongerStringYieldsWiderColumn() {
        let short = TableLayout.columnWidths(header: ["Machine"], rows: [["the-zen"]])[0]
        let longer = TableLayout.columnWidths(header: ["Machine"],
                                              rows: [["the-zen (Mac Studio, main workstation)"]])[0]
        XCTAssertGreaterThan(longer, short)
        XCTAssertLessThanOrEqual(longer, TableLayout.maxColumnWidth)
        XCTAssertGreaterThanOrEqual(short, TableLayout.minColumnWidth)
    }

    func testEveryColumnStaysWithinTheClampBounds() {
        let long = String(repeating: "x", count: 400)
        let widths = TableLayout.columnWidths(header: ["Machine", "RAM", "GPU", "Role"],
                                              rows: [["studio-pc", "128 GB", "RTX 4090", long],
                                                     ["the-zen", "64 GB", "M2 Max", "daily driver"]])
        XCTAssertEqual(widths.count, 4)
        for width in widths {
            XCTAssertGreaterThanOrEqual(width, TableLayout.minColumnWidth)
            XCTAssertLessThanOrEqual(width, TableLayout.maxColumnWidth)
        }
        XCTAssertEqual(widths[3], TableLayout.maxColumnWidth)
    }

    func testHeaderWidthCountsWhenItIsTheWidestCell() {
        let headerOnly = TableLayout.columnWidths(header: ["A considerably longer header label"],
                                                  rows: [["x"]])[0]
        XCTAssertGreaterThan(headerOnly, TableLayout.minColumnWidth)
    }

    func testRaggedRowsDoNotLoseColumnsAndEmptyTableIsEmpty() {
        let widths = TableLayout.columnWidths(header: ["A", "B"], rows: [["one"], ["one", "two", "three"]])
        XCTAssertEqual(widths.count, 3)
        XCTAssertTrue(TableLayout.columnWidths(header: [] as [String], rows: []).isEmpty)
    }

    func testTotalWidthAddsTheGapsBetweenColumns() {
        XCTAssertEqual(TableLayout.totalWidth([]), 0)
        XCTAssertEqual(TableLayout.totalWidth([100]), 100)
        XCTAssertEqual(TableLayout.totalWidth([100, 200]), 300 + TableLayout.columnSpacing)
    }

    func testCodeCellsAreMeasuredWiderThanTheSameTextInTheSystemFont() {
        let text = "mavis-trash --restore"
        let plain = TableLayout.columnWidths(header: [TableLayout.Cell("Command")],
                                             rows: [[TableLayout.Cell(text)]])[0]
        let code = TableLayout.columnWidths(header: [TableLayout.Cell("Command")],
                                            rows: [[TableLayout.Cell(text, isCode: true)]])[0]
        XCTAssertGreaterThan(code, plain)
        XCTAssertLessThanOrEqual(code, TableLayout.maxColumnWidth)
    }

    func testStringConvenienceMatchesNonCodeCells() {
        let viaStrings = TableLayout.columnWidths(header: ["Machine"], rows: [["the-zen (Mac Studio)"]])
        let viaCells = TableLayout.columnWidths(header: [TableLayout.Cell("Machine")],
                                                rows: [[TableLayout.Cell("the-zen (Mac Studio)")]])
        XCTAssertEqual(viaStrings, viaCells)
    }
}
