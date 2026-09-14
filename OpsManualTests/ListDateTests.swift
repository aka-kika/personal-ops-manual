import XCTest
@testable import OpsManual

final class ListDateTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Lisbon")!; c.locale = Locale(identifier: "en_GB"); return c }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 5) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testSameDayShowsTime() {
        XCTAssertEqual(ListDate.format(date(2026, 9, 13, 14, 7), now: date(2026, 9, 13, 18), calendar: cal), "14:07")
    }
    func testSameYearShowsDayMonth() {
        XCTAssertEqual(ListDate.format(date(2026, 3, 2), now: date(2026, 9, 13), calendar: cal), "2 Mar")
    }
    func testOtherYearAddsYear() {
        XCTAssertEqual(ListDate.format(date(2025, 12, 24), now: date(2026, 9, 13), calendar: cal), "24 Dec 2025")
    }
}

final class ReaderDateTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Lisbon")!; c.locale = Locale(identifier: "en_GB"); return c }

    /// Matches doc-viewer.tsx's en-GB toLocaleDateString output.
    func testFormatsAsDayMonthYearAtTime() {
        let date = cal.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 20, minute: 20))!
        XCTAssertEqual(ReaderDate.format(date, calendar: cal), "13 Sep 2026 at 20:20")
    }

    func testPadsTheHourAndKeepsTheDayUnpadded() {
        let date = cal.date(from: DateComponents(year: 2025, month: 12, day: 3, hour: 9, minute: 5))!
        XCTAssertEqual(ReaderDate.format(date, calendar: cal), "3 Dec 2025 at 09:05")
    }
}
