import XCTest
import Markdown
@testable import OpsManual

final class MarkdownInlineTests: XCTestCase {
    func paragraph(_ md: String) -> Paragraph {
        Markdown.Document(parsing: md).child(at: 0) as! Paragraph
    }

    func testPlainTextAndStrong() {
        let a = MarkdownInline.attributed(paragraph("hello **bold** world"))
        XCTAssertEqual(String(a.characters), "hello bold world")
        let boldRun = a.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertEqual(boldRun.map { String(a[$0.range].characters) }, "bold")
    }

    func testInlineCodeGetsCodeIntent() {
        let a = MarkdownInline.attributed(paragraph("run `ls -la` now"))
        let codeRun = a.runs.first { $0.inlinePresentationIntent?.contains(.code) == true }
        XCTAssertEqual(codeRun.map { String(a[$0.range].characters) }, "ls -la")
    }

    func testDocLinkAndWebLinkCarryURLs() {
        let a = MarkdownInline.attributed(paragraph("[Doc](opsmanual://doc/abc) and [Web](https://x.y)"))
        let links = a.runs.compactMap(\.link).map(\.absoluteString)
        XCTAssertEqual(links, ["opsmanual://doc/abc", "https://x.y"])
    }

    func testSoftBreakBecomesSpace() {
        let a = MarkdownInline.attributed(paragraph("line one\nline two"))
        XCTAssertEqual(String(a.characters), "line one line two")
    }

    func testNestedEmphasisInsideStrongKeepsBothIntents() {
        let a = MarkdownInline.attributed(paragraph("**important: *really* important**"))
        let inner = a.runs.first { String(a[$0.range].characters) == "really" }
        XCTAssertEqual(inner?.inlinePresentationIntent, [.stronglyEmphasized, .emphasized])
        let outer = a.runs.first { String(a[$0.range].characters).hasPrefix("important: ") }
        XCTAssertEqual(outer?.inlinePresentationIntent, [.stronglyEmphasized])
    }
}
