import XCTest
@testable import OpsManual

final class FrontmatterCodecTests: XCTestCase {
    let sample = """
    ---
    title: A launch agent is down
    category: Recovery
    summary: Restart or inspect a launchd job
    tags:
      - recovery
      - launchd
    createdAt: 2026-09-13T13:30:00.000Z
    updatedAt: 2026-09-13T13:30:00.000Z
    id: mtzs3wy5-r3584k
    type: ops-doc
    date: 2026-09-13
    status: active
    ---

    One sentence.

    ## Steps

    - `launchctl list | grep myjob`
    """

    func testParseKnownFields() throws {
        let doc = try XCTUnwrap(FrontmatterCodec.document(from: sample))
        XCTAssertEqual(doc.id, "mtzs3wy5-r3584k")
        XCTAssertEqual(doc.title, "A launch agent is down")
        XCTAssertEqual(doc.category, "Recovery")
        XCTAssertEqual(doc.summary, "Restart or inspect a launchd job")
        XCTAssertEqual(doc.tags, ["recovery", "launchd"])
        XCTAssertEqual(doc.properties.map(\.key), ["type", "date", "status"])
        XCTAssertEqual(doc.properties[2].value, "active")
        XCTAssertTrue(doc.body.hasPrefix("One sentence."))
    }

    func testRoundTripIsByteIdentical() throws {
        let doc = try XCTUnwrap(FrontmatterCodec.document(from: sample))
        XCTAssertEqual(FrontmatterCodec.serialize(doc), sample)
    }

    func testQuotingRule() {
        XCTAssertEqual(FrontmatterCodec.escape("plain words"), "plain words")
        XCTAssertEqual(FrontmatterCodec.escape("has: colon"), "\"has: colon\"")
        XCTAssertEqual(FrontmatterCodec.escape("say \"hi\""), "\"say \\\"hi\\\"\"")
        XCTAssertEqual(FrontmatterCodec.escape("it's"), "\"it's\"")
    }

    func testEmptyTagsSerializeAsBracket() {
        var doc = FrontmatterCodec.document(from: sample)!
        doc.tags = []
        doc.summary = ""
        let out = FrontmatterCodec.serialize(doc)
        XCTAssertTrue(out.contains("\ntags:\n  []\ncreatedAt:"))
        XCTAssertFalse(out.contains("summary:"))
    }

    func testInlineTagsParse() {
        let raw = "---\ntitle: T\ncategory: C\ntags: [a, b]\ncreatedAt: x\nupdatedAt: y\nid: z\n---\nbody"
        XCTAssertEqual(FrontmatterCodec.document(from: raw)?.tags, ["a", "b"])
    }

    func testMissingIdReturnsNil() {
        XCTAssertNil(FrontmatterCodec.document(from: "---\ntitle: T\n---\nbody"))
    }

    func testFileNameAndSlug() {
        XCTAssertEqual(OpsDocument.slugify("Hello, World! 2026"), "hello-world-2026")
        XCTAssertEqual(OpsDocument.slugify("###"), "untitled")
        let doc = FrontmatterCodec.document(from: sample)!
        XCTAssertEqual(doc.fileName, "a-launch-agent-is-down-mtzs3wy5-r3584k.md")
    }

    func testMakeIDShape() {
        let id = OpsDocument.makeID()
        let parts = id.split(separator: "-")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[1].count, 6)
    }

    /// Every real manual page must survive a round trip unchanged.
    func testRealFolderRoundTrip() throws {
        // Set OPS_MANUAL_TEST_DIR to a real pages folder to run this against live data.
        guard let dirPath = ProcessInfo.processInfo.environment["OPS_MANUAL_TEST_DIR"], !dirPath.isEmpty else {
            throw XCTSkip("OPS_MANUAL_TEST_DIR not set")
        }
        let dir = URL(fileURLWithPath: dirPath)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            throw XCTSkip("pages folder not present")
        }
        var failures: [String] = []
        for name in names where name.hasSuffix(".md") {
            let raw = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            guard let doc = FrontmatterCodec.document(from: raw) else { failures.append("\(name): no id"); continue }
            if FrontmatterCodec.serialize(doc) != raw { failures.append(name) }
        }
        XCTAssertTrue(failures.isEmpty, "Not byte-identical: \(failures)")
    }
}
