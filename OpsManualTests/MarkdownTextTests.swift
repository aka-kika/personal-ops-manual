import XCTest
@testable import OpsManual

final class MarkdownTextTests: XCTestCase {
    func testExcerptSkipsHeadingsFencesTablesRules() {
        let body = """
        # Title

        ```
        code
        ```
        | a | b |
        ---
        - **First** real `line` here
        """
        XCTAssertEqual(MarkdownText.excerpt(of: body), "First real line here")
    }

    func testExcerptCutsAt140() {
        let long = String(repeating: "x", count: 200)
        let out = MarkdownText.excerpt(of: long)
        XCTAssertEqual(out.count, 138)
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func testExcerptEmptyBody() {
        XCTAssertEqual(MarkdownText.excerpt(of: "## only\n\n```\nx\n```"), "")
    }

    func testStripMarkdown() {
        XCTAssertEqual(MarkdownText.strip("**bold** and [link](http://x) `code`"), "bold and link code")
    }

    func testStripLeadingTitle() {
        XCTAssertEqual(MarkdownText.stripLeadingTitle("# Same\n\nrest", title: "Same"), "rest")
        XCTAssertEqual(MarkdownText.stripLeadingTitle("# Other\n\nrest", title: "Same"), "# Other\n\nrest")
    }
}
