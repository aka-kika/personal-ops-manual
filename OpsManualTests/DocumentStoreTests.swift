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

    func testCreateWritesFileWithSlugAndId() throws {
        let store = DocumentStore(folder: dir, watch: false)
        var draft = DocDraft()
        draft.title = "New Page!"
        draft.category = "Ops"
        draft.body = "Hello"
        let doc = try store.create(draft)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new-page-\(doc.id).md").path))
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.excerpt(for: doc), "Hello")
    }

    func testUpdateRenamesFileWhenTitleChanges() throws {
        try write("old-1.md", page("Old", id: "1", body: "x"))
        let store = DocumentStore(folder: dir, watch: false)
        var draft = DocDraft(document: store.document(id: "1")!)
        draft.title = "Renamed"
        let updated = try store.update(id: "1", draft: draft)
        XCTAssertEqual(updated.title, "Renamed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old-1.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("renamed-1.md").path))
        XCTAssertEqual(updated.createdAt, "2026-09-13T10:00:00.000Z")
        XCTAssertNotEqual(updated.updatedAt, "2026-09-13T10:00:00.000Z")
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

    func testBacklinksAndTitleLookup() throws {
        try write("t-1.md", page("Target Page", id: "1", body: "x"))
        try write("s-2.md", page("Source", id: "2", body: "see [[target page|it]]"))
        try write("o-3.md", page("Other", id: "3", body: "no links"))
        let store = DocumentStore(folder: dir, watch: false)
        XCTAssertEqual(store.backlinks(for: "1").map(\.id), ["2"])
        XCTAssertEqual(store.idForTitle("TARGET page"), "1")
        XCTAssertNil(store.idForTitle("missing"))
    }

    func testHandNamedFileIsUpdatedAndTrashedInPlace() throws {
        try write("WEIRD name.md", page("Tidy", id: "7", body: "x"))
        let store = DocumentStore(folder: dir, watch: false)
        XCTAssertEqual(store.fileURL(for: store.document(id: "7")!).lastPathComponent, "WEIRD name.md")
        var draft = DocDraft(document: store.document(id: "7")!)
        draft.body = "changed"
        try store.update(id: "7", draft: draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("WEIRD name.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("tidy-7.md").path))
        try store.trash(id: "7")
        XCTAssertEqual(store.documents.count, 0)
    }

    func testUpdateThrowsWhenTheIdIsGone() throws {
        let store = DocumentStore(folder: dir, watch: false)
        XCTAssertThrowsError(try store.update(id: "missing", draft: DocDraft())) { error in
            guard case DocumentStoreError.documentNotFound(let id) = error else {
                return XCTFail("expected documentNotFound, got \(error)")
            }
            XCTAssertEqual(id, "missing")
            XCTAssertFalse((error as? LocalizedError)?.errorDescription?.isEmpty ?? true)
        }
    }

    /// The new file is written before the old one is removed, so a write that
    /// cannot land leaves the document on disk untouched.
    func testFailedWriteLeavesTheOriginalFileInPlace() throws {
        try write("old-1.md", page("Old", id: "1", body: "original body"))
        let store = DocumentStore(folder: dir, watch: false)
        var draft = DocDraft(document: store.document(id: "1")!)
        draft.title = "Renamed"
        draft.body = "new body"

        let original = try String(contentsOf: dir.appendingPathComponent("old-1.md"), encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        XCTAssertThrowsError(try store.update(id: "1", draft: draft))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old-1.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("renamed-1.md").path))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("old-1.md"), encoding: .utf8), original)
    }

    /// `fileURL(for:)` returns the name on disk, `newURL` the lowercase slug. On a
    /// case-insensitive volume those are the same directory entry even though the
    /// strings differ, so removing the old URL after the write deletes what was
    /// just written.
    func testCaseOnlyRenameKeepsTheFile() throws {
        try write("Weird-Name-7.md", page("Weird Name", id: "7", body: "original"))
        let store = DocumentStore(folder: dir, watch: false)
        var draft = DocDraft(document: store.document(id: "7")!)
        draft.body = "changed"
        try store.update(id: "7", draft: draft)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".md") }
        XCTAssertEqual(files.count, 1, "expected one file, found \(files)")
        let contents = try String(contentsOf: dir.appendingPathComponent(files[0]), encoding: .utf8)
        XCTAssertTrue(contents.contains("changed"))
        XCTAssertEqual(store.documents.count, 1)
    }

    func testTrashRemovesFromFolder() throws {
        try write("t-1.md", page("T", id: "1", body: "x"))
        let store = DocumentStore(folder: dir, watch: false)
        try store.trash(id: "1")
        XCTAssertEqual(store.documents.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("t-1.md").path))
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
    }
}
