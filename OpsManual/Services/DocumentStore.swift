import Foundation
import Observation

struct SearchHit: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let snippet: String
}

struct BacklinkRef: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
}

enum DocumentStoreError: LocalizedError {
    case documentNotFound(id: String)

    var errorDescription: String? {
        switch self {
        case .documentNotFound(let id):
            "No document with id \(id) is in the folder any more. It may have been renamed, moved or removed outside the app."
        }
    }
}

/// The folder is the source of truth. The store reads every `.md` with an `id`,
/// writes atomically in the Node app's exact format, and reloads when the folder changes.
@MainActor
@Observable
final class DocumentStore {
    private(set) var folder: URL
    private(set) var documents: [OpsDocument] = []
    private(set) var loadError: String?
    /// Open lines in `_inbox/reports.md`, the reports readers filed through the MCP.
    private(set) var inboxOpenCount = 0
    @ObservationIgnored private var inboxWatcher: FolderWatcher?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private let shouldWatch: Bool
    /// id -> file name actually on disk (hand-named files may not match the slug rule).
    @ObservationIgnored private var fileNames: [String: String] = [:]

    init(folder: URL, watch: Bool = true) {
        self.folder = folder
        self.shouldWatch = watch
        load()
        startWatching()
    }

    var categories: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for doc in documents { counts[doc.category, default: 0] += 1 }
        return counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ($0, counts[$0]!) }
    }

    func document(id: String) -> OpsDocument? { documents.first { $0.id == id } }

    func fileURL(for doc: OpsDocument) -> URL {
        folder.appendingPathComponent(fileNames[doc.id] ?? doc.fileName)
    }

    func excerpt(for doc: OpsDocument) -> String {
        doc.summary.isEmpty ? MarkdownText.excerpt(of: doc.body) : doc.summary
    }

    func setFolder(_ url: URL) {
        watcher?.stop()
        inboxWatcher?.stop()
        folder = url
        load()
        startWatching()
    }

    func load() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            var docs: [OpsDocument] = []
            var names0: [String: String] = [:]
            for name in names where name.hasSuffix(".md") {
                guard let raw = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8),
                      let doc = FrontmatterCodec.document(from: raw) else { continue }
                docs.append(doc)
                names0[doc.id] = name
            }
            fileNames = names0
            documents = docs.sorted { $0.updatedDate > $1.updatedDate }
            loadError = nil
            inboxOpenCount = countOpenReports()
        } catch {
            documents = []
            loadError = error.localizedDescription
        }
    }

    static let inboxFolderName = "_inbox"
    static let inboxFileName = "reports.md"
    var inboxFileURL: URL { folder.appendingPathComponent(Self.inboxFolderName).appendingPathComponent(Self.inboxFileName) }

    private func countOpenReports() -> Int {
        guard let raw = try? String(contentsOf: inboxFileURL, encoding: .utf8) else { return 0 }
        return raw.split(separator: "\n").filter { $0.hasPrefix("- [ ] ") }.count
    }

    private func startWatching() {
        guard shouldWatch else { watcher = nil; inboxWatcher = nil; return }
        let inboxDir = folder.appendingPathComponent(Self.inboxFolderName)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        inboxWatcher = FolderWatcher(url: inboxDir) { [weak self] in self?.load() }
        watcher = FolderWatcher(url: folder) { [weak self] in self?.load() }
    }

    @discardableResult
    func create(_ draft: DocDraft) throws -> OpsDocument {
        let now = FrontmatterCodec.nowISO()
        let doc = OpsDocument(
            id: OpsDocument.makeID(),
            title: draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : draft.title.trimmingCharacters(in: .whitespaces),
            category: draft.category.trimmingCharacters(in: .whitespaces).isEmpty ? "Uncategorized" : draft.category.trimmingCharacters(in: .whitespaces),
            summary: draft.summary,
            tags: draft.tags,
            createdAt: now,
            updatedAt: now,
            properties: draft.properties,
            body: draft.body)
        try write(doc, to: folder.appendingPathComponent(doc.fileName))
        load()
        return doc
    }

    /// Writes the new file first and only then removes the old one when the
    /// name changed: a failed write must never cost the document on disk.
    ///
    /// The two URLs are compared by file identity, not by string. `fileURL(for:)`
    /// gives the name actually on disk while `newURL` is the lowercase slug, so a
    /// hand-named `Weird-Name-7.md` and its slug `weird-name-7.md` differ as strings
    /// yet are the same directory entry on a case-insensitive volume — removing the
    /// "old" one there would delete the file that was just written.
    @discardableResult
    func update(id: String, draft: DocDraft) throws -> OpsDocument {
        guard let existing = document(id: id) else { throw DocumentStoreError.documentNotFound(id: id) }
        var updated = existing
        updated.title = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : draft.title.trimmingCharacters(in: .whitespaces)
        updated.category = draft.category.trimmingCharacters(in: .whitespaces).isEmpty ? "Uncategorized" : draft.category.trimmingCharacters(in: .whitespaces)
        updated.summary = draft.summary
        updated.tags = draft.tags
        updated.properties = draft.properties
        updated.body = draft.body
        updated.updatedAt = FrontmatterCodec.nowISO()
        let oldURL = fileURL(for: existing)
        let newURL = folder.appendingPathComponent(updated.fileName)
        try write(updated, to: newURL)
        if oldURL != newURL, !isSameFile(oldURL, newURL) {
            try? FileManager.default.removeItem(at: oldURL)
        }
        load()
        return updated
    }

    func trash(id: String) throws {
        guard let doc = document(id: id) else { return }
        try FileManager.default.trashItem(at: fileURL(for: doc), resultingItemURL: nil)
        load()
    }

    /// Case-insensitive substring over title, category, tags and body; snippet around the first body hit; sorted by title.
    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for doc in documents {
            let haystack = "\(doc.title)\n\(doc.category)\n\(doc.tags.joined(separator: " "))\n\(doc.body)".lowercased()
            guard haystack.contains(q) else { continue }
            let body = doc.body
            var snippet: String
            if let r = body.lowercased().range(of: q) {
                let lower = body.lowercased()
                let startOffset = max(0, lower.distance(from: lower.startIndex, to: r.lowerBound) - 40)
                let endOffset = min(body.count, lower.distance(from: lower.startIndex, to: r.upperBound) + 60)
                let s = body.index(body.startIndex, offsetBy: startOffset)
                let e = body.index(body.startIndex, offsetBy: endOffset)
                snippet = (startOffset > 0 ? "…" : "") + body[s..<e].trimmingCharacters(in: .whitespacesAndNewlines) + (endOffset < body.count ? "…" : "")
            } else {
                snippet = String(body.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            hits.append(SearchHit(id: doc.id, title: doc.title, category: doc.category, snippet: MarkdownText.strip(snippet)))
        }
        return hits.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func idForTitle(_ title: String) -> String? {
        let wanted = title.trimmingCharacters(in: .whitespaces).lowercased()
        return documents.first { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == wanted }?.id
    }

    func backlinks(for id: String) -> [BacklinkRef] {
        guard let target = document(id: id) else { return [] }
        let wanted = target.title.trimmingCharacters(in: .whitespaces).lowercased()
        return documents
            .filter { $0.id != id && WikiLinks.linkedTitles(in: $0.body).contains { $0.lowercased() == wanted } }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { BacklinkRef(id: $0.id, title: $0.title, category: $0.category) }
    }

    /// True when both URLs resolve to the same file on disk. Identifiers are only
    /// meaningful for files that exist, so a missing one answers false and leaves the
    /// caller's own `oldURL != newURL` check in charge.
    private func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let a = try? lhs.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let b = try? rhs.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else { return false }
        return a.isEqual(b)
    }

    private func write(_ doc: OpsDocument, to url: URL) throws {
        let data = Data(FrontmatterCodec.serialize(doc).utf8)
        try data.write(to: url, options: .atomic)
    }
}
