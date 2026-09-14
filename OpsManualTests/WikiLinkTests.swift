import XCTest
@testable import OpsManual

final class WikiLinkTests: XCTestCase {
    let ids = ["ports and services": "id1", "tailscale": "id2"]

    func testResolvePlainAndAliased() {
        let body = "See [[Ports and services]] and [[Tailscale|the tailnet]]."
        let out = WikiLinks.resolve(body) { ids[$0.lowercased()] }
        XCTAssertEqual(out, "See [Ports and services](opsmanual://doc/id1) and [the tailnet](opsmanual://doc/id2).")
    }

    func testUnresolvedBecomesPlainText() {
        let out = WikiLinks.resolve("[[Nowhere]]") { _ in nil }
        XCTAssertEqual(out, "Nowhere")
    }

    func testLinkedTitles() {
        XCTAssertEqual(WikiLinks.linkedTitles(in: "[[A]] x [[ B |lbl]]"), ["A", "B"])
    }

    func testInlineCodeStaysLiteral() {
        let body = "Write `[[Tailscale]]` to link, like [[Tailscale]]."
        let out = WikiLinks.resolve(body) { ids[$0.lowercased()] }
        XCTAssertEqual(out, "Write `[[Tailscale]]` to link, like [Tailscale](opsmanual://doc/id2).")
    }

    func testFencedCodeStaysLiteral() {
        let body = "```\n[[Tailscale]]\n[[Ports and services]]\n```\nAfter: [[Tailscale]]"
        let out = WikiLinks.resolve(body) { ids[$0.lowercased()] }
        XCTAssertEqual(out, "```\n[[Tailscale]]\n[[Ports and services]]\n```\nAfter: [Tailscale](opsmanual://doc/id2)")
    }

    func testLinkedTitlesIgnoresCode() {
        let body = "`[[Hidden]]` and ```\n[[AlsoHidden]]\n``` but [[Visible]]"
        XCTAssertEqual(WikiLinks.linkedTitles(in: body), ["Visible"])
    }

    func testUnresolvedInsideCodeIsNotStripped() {
        XCTAssertEqual(WikiLinks.resolve("`[[Nowhere]]`") { _ in nil }, "`[[Nowhere]]`")
    }

    func testDocURLRoundTrip() {
        let url = WikiLinks.url(forDoc: "abc-123")
        XCTAssertEqual(url.absoluteString, "opsmanual://doc/abc-123")
        XCTAssertEqual(WikiLinks.docID(from: url), "abc-123")
        XCTAssertNil(WikiLinks.docID(from: URL(string: "https://example.com")!))
    }
}
