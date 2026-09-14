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

    func testDraftFromMarkdownUsesFrontmatterThenH1ThenStem() {
        let withFm = "---\ntitle: FM Title\ncategory: Cat\nowner: me\nid: abc\n---\n# H1\nbody"
        let d1 = MarkdownText.draft(fromMarkdown: withFm, fileName: "any.md")
        XCTAssertEqual(d1.title, "FM Title")
        XCTAssertEqual(d1.category, "Cat")
        XCTAssertEqual(d1.properties, [DocProperty(key: "owner", value: "me")])
        XCTAssertTrue(d1.body.hasPrefix("# H1"))

        let d2 = MarkdownText.draft(fromMarkdown: "# From H1\n\ntext", fileName: "x.md")
        XCTAssertEqual(d2.title, "From H1")

        let d3 = MarkdownText.draft(fromMarkdown: "plain", fileName: "my_notes-file.markdown")
        XCTAssertEqual(d3.title, "my notes file")
    }

    func testStripLeadingTitle() {
        XCTAssertEqual(MarkdownText.stripLeadingTitle("# Same\n\nrest", title: "Same"), "rest")
        XCTAssertEqual(MarkdownText.stripLeadingTitle("# Other\n\nrest", title: "Same"), "# Other\n\nrest")
    }
}
