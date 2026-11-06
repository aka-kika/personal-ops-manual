import XCTest
@testable import OpsManual

/// The What's new sheet: shown once after an update, never on a first install.
final class WhatsNewTests: XCTestCase {
    func testParsesHeadingsAndBulletsAndSkipsTheInstallLine() {
        let notes = """
        Notarized Developer ID build for macOS 26 or newer. Unzip, then drag Personal Ops Manual.app to Applications.

        New in 0.6.1
        - **Previews for repos and sites:** a picture in the list.

        Changes in 0.6.1
        - **The list view switch works.**
        """
        let lines = WhatsNew.parse(notes)
        XCTAssertEqual(lines.count, 4)
        // A long heading stays a heading (0.5.2's had 99 characters).
        let long = WhatsNew.parse("Fixes in 0.5.2 (the second Argon code review, all 15 items, plus one freeze found while testing)\n- **One:** fix.")
        XCTAssertEqual(long.first, .heading("Fixes in 0.5.2 (the second Argon code review, all 15 items, plus one freeze found while testing)"))
        XCTAssertEqual(lines.first, .heading("New in 0.6.1"))
        if case .bullet(let text) = lines[1] {
            XCTAssertEqual(String(text.characters), "Previews for repos and sites: a picture in the list.")
        } else {
            XCTFail("expected a bullet")
        }
    }

    func testShownOnceAfterAnUpdateNeverOnFirstInstall() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ops-whatsnew-\(UUID().uuidString)"))
        // The tests run inside the app, so its version and its notes are in Bundle.main.
        // A first install only remembers the version.
        XCTAssertFalse(WhatsNew.shouldShow(defaults: defaults))
        XCTAssertFalse(WhatsNew.shouldShow(defaults: defaults))
        // After an update the sheet shows once, then not again.
        defaults.set("0.0.1", forKey: WhatsNew.lastSeenKey)
        XCTAssertTrue(WhatsNew.shouldShow(defaults: defaults))
        WhatsNew.markSeen(defaults: defaults)
        XCTAssertFalse(WhatsNew.shouldShow(defaults: defaults))
    }

    func testThisVersionHasNotesInTheApp() {
        XCTAssertNotNil(WhatsNew.notes(for: WhatsNew.currentVersion), "docs/release-notes/<version>.md is missing from the bundle")
    }
}
