import XCTest
@testable import OpsManual

@MainActor
final class DocumentStoreTests: XCTestCase {
    var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("opsmanual-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ name: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func page(_ title: String, id: String, category: String = "Ops", body: String, updated: String = "2026-09-13T10:00:00.000Z") -> String {
        "---\ntitle: \(title)\ncategory: \(category)\ntags:\n  []\ncreatedAt: \(updated)\nupdatedAt: \(updated)\nid: \(id)\n---\n\n\(body)\n"
    }

    func testLoadSortsAndCounts() throws {
        try write("a-1.md", page("A", id: "1", category: "Zeta", body: "a", updated: "2026-09-13T10:00:00.000Z"))
        try write("b-2.md", page("B", id: "2", category: "Alpha", body: "b", updated: "2026-09-13T12:00:00.000Z"))
        try write("notes.txt", "ignored")
        let store = DocumentStore(folder: dir, watch: false)
        XCTAssertEqual(store.documents.map(\.id), ["2", "1"])
        XCTAssertEqual(store.categories.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(store.categories.map(\.count), [1, 1])
    }

    func testSearchMatchesTitleTagsBodyAndSortsByTitle() throws {
        try write("z-1.md", page("Zebra", id: "1", body: "nothing here"))
        try write("a-2.md", page("Apple", id: "2", body: "the zebra crossing is long"))
        let store = DocumentStore(folder: dir, watch: false)
        let hits = store.search("zebra")
        XCTAssertEqual(hits.map(\.title), ["Apple", "Zebra"])
        XCTAssertTrue(hits[0].snippet.contains("zebra crossing"))
        XCTAssertEqual(store.search("   "), [])
    }

    func testSearchMatchesSummary() throws {
        try write("a-1.md", "---\ntitle: Alpha\ncategory: Ops\nsummary: Restart the gateway\ntags:\n  []\ncreatedAt: 2026-09-13T10:00:00.000Z\nupdatedAt: 2026-09-13T10:00:00.000Z\nid: 1\n---\n\nbody\n")
        let store = DocumentStore(folder: dir, watch: false)
        let hits = store.search("gateway")
        XCTAssertEqual(hits.map(\.title), ["Alpha"])
        XCTAssertEqual(hits.first?.snippet, "Restart the gateway")
    }

    func testMissingDatesFallBackToTheFileDate() throws {
        try write("a-1.md", "---\ntitle: Hand made\ncategory: Ops\nid: 1\n---\n\nbody\n")
        try write("b-2.md", page("Dated", id: "2", body: "b", updated: "2025-01-01T00:00:00.000Z"))
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.appendingPathComponent("a-1.md").path)
        let store = DocumentStore(folder: dir, watch: false)
        let doc = try XCTUnwrap(store.document(id: "1"))
        XCTAssertEqual(doc.updatedAt, FrontmatterCodec.isoFormatter.string(from: old))
        XCTAssertEqual(doc.createdAt, doc.updatedAt)
        XCTAssertEqual(store.documents.map(\.id), ["2", "1"])
    }

    func testBacklinksAndTitleLookup() throws {
        try write("t-1.md", page("Target Page", id: "1", body: "x"))
        try write("s-2.md", page("Source", id: "2", body: "see [[target page|it]]"))
        try write("o-3.md", page("Other", id: "3", body: "no links"))
        let store = DocumentStore(folder: dir, watch: false)
        XCTAssertEqual(store.backlinks(for: "1").map(\.id), ["2"])
        XCTAssertEqual(store.idForTitle("TARGET page"), "1")
        XCTAssertNil(store.idForTitle("missing"))
    }

    /// A folder that cannot be opened must report itself inactive rather than
    /// pretending to watch (the failure is logged, not swallowed).
    func testWatcherIsInactiveWhenTheFolderCannotBeOpened() {
        let missing = dir.appendingPathComponent("does-not-exist")
        let watcher = FolderWatcher(url: missing) {}
        XCTAssertFalse(watcher.isActive)
        watcher.stop()
        XCTAssertTrue(FolderWatcher(url: dir) {}.isActive)
    }

    func testWatcherReloadsOnExternalWrite() async throws {
        let store = DocumentStore(folder: dir, watch: true)
        XCTAssertEqual(store.documents.count, 0)
        try write("n-9.md", page("N", id: "9", body: "x"))
        for _ in 0..<40 where store.documents.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.documents.map(\.id), ["9"])

        let handle = try FileHandle(forWritingTo: dir.appendingPathComponent("n-9.md"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nappended line\n".utf8))
        try handle.close()
        for _ in 0..<40 where !(store.document(id: "9")?.body.contains("appended line") ?? false) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(store.document(id: "9")?.body.contains("appended line") == true)
    }
}
