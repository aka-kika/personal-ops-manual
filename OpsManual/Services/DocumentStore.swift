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
    case invalidDocumentID(id: String)
    case invalidPropertyKey(key: String)

    var errorDescription: String? {
        switch self {
        case .documentNotFound(let id):
            "No document with id \(id) is in the folder any more. It may have been renamed, moved or removed outside the app."
        case .invalidDocumentID(let id):
            "Document id \"\(id)\" is not allowed."
        case .invalidPropertyKey(let key):
            "Property key \"\(key)\" is reserved or invalid."
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

    func document(filePath: String) -> OpsDocument? { documents.first { $0.filePath == filePath } }

    func fileURL(for doc: OpsDocument) -> URL {
        if !doc.filePath.isEmpty {
            return URL(fileURLWithPath: doc.filePath)
        }
        if let existing = document(id: doc.id), !existing.filePath.isEmpty {
            return URL(fileURLWithPath: existing.filePath)
        }
        return folder.appendingPathComponent(doc.fileName)
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
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            var docs: [OpsDocument] = []
            for name in names where name.hasSuffix(".md") {
                let url = folder.appendingPathComponent(name)
                let fileDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
                guard let raw = try? String(contentsOf: url, encoding: .utf8),
                      var doc = FrontmatterCodec.document(from: raw, fileDate: fileDate) else { continue }
                doc.filePath = url.path
                docs.append(doc)
            }
            documents = docs.sorted {
                if $0.updatedDate != $1.updatedDate { return $0.updatedDate > $1.updatedDate }
                return $0.filePath < $1.filePath
            }
            loadError = nil
            inboxOpenCount = countOpenReports()
            if shouldWatch, inboxWatcher?.isActive != true {
                let inboxDir = folder.appendingPathComponent(Self.inboxFolderName)
                if FileManager.default.fileExists(atPath: inboxDir.path) {
                    inboxWatcher = FolderWatcher(url: inboxDir) { [weak self] in self?.load() }
                }
            }
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
        try ensureUnlocked()
        try validateProperties(draft.properties)
        let now = FrontmatterCodec.nowISO()
        let title = FrontmatterCodec.singleLine(draft.title).trimmingCharacters(in: .whitespaces)
        let category = FrontmatterCodec.singleLine(draft.category).trimmingCharacters(in: .whitespaces)
        var doc = OpsDocument(
            id: OpsDocument.makeID(),
            title: title.isEmpty ? "Untitled" : title,
            category: category.isEmpty ? "Uncategorized" : category,
            summary: FrontmatterCodec.singleLine(draft.summary),
            tags: draft.tags.map(FrontmatterCodec.singleLine),
            createdAt: now,
            updatedAt: now,
            properties: draft.properties.map {
                DocProperty(
                    key: FrontmatterCodec.singleLine($0.key).trimmingCharacters(in: .whitespaces),
                    value: FrontmatterCodec.singleLine($0.value))
            },
            body: draft.body)
        let url = folder.appendingPathComponent(doc.fileName)
        doc.filePath = url.path
        try write(doc, to: url)
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
    func update(filePath: String, draft: DocDraft) throws -> OpsDocument {
        try ensureUnlocked()
        guard let existing = document(filePath: filePath) else {
            throw DocumentStoreError.documentNotFound(id: filePath)
        }
        return try updateDocument(existing, draft: draft)
    }

    @discardableResult
    func update(id: String, draft: DocDraft) throws -> OpsDocument {
        try ensureUnlocked()
        guard let existing = document(id: id) else { throw DocumentStoreError.documentNotFound(id: id) }
        return try updateDocument(existing, draft: draft)
    }

    private func updateDocument(_ existing: OpsDocument, draft: DocDraft) throws -> OpsDocument {
        try validateProperties(draft.properties)
        let title = FrontmatterCodec.singleLine(draft.title).trimmingCharacters(in: .whitespaces)
        let category = FrontmatterCodec.singleLine(draft.category).trimmingCharacters(in: .whitespaces)
        var updated = existing
        updated.title = title.isEmpty ? "Untitled" : title
        updated.category = category.isEmpty ? "Uncategorized" : category
        updated.summary = FrontmatterCodec.singleLine(draft.summary)
        updated.tags = draft.tags.map(FrontmatterCodec.singleLine)
        updated.properties = draft.properties.map {
            DocProperty(
                key: FrontmatterCodec.singleLine($0.key).trimmingCharacters(in: .whitespaces),
                value: FrontmatterCodec.singleLine($0.value))
        }
        updated.body = draft.body
        updated.updatedAt = FrontmatterCodec.nowISO()
        let oldURL = fileURL(for: existing)
        let candidateURL = folder.appendingPathComponent(updated.fileName)
        let newURL: URL
        if candidateURL != oldURL,
           FileManager.default.fileExists(atPath: candidateURL.path),
           !isSameFile(oldURL, candidateURL) {
            newURL = oldURL
        } else {
            newURL = candidateURL
        }
        updated.filePath = newURL.path
        try write(updated, to: newURL)
        if oldURL != newURL, !isSameFile(oldURL, newURL) {
            do {
                try FileManager.default.removeItem(at: oldURL)
            } catch {
                try? FileManager.default.removeItem(at: newURL)
                throw error
            }
        }
        load()
        return updated
    }

    func trash(filePath: String) throws {
        try ensureUnlocked()
        guard let doc = document(filePath: filePath) else { return }
        try FileManager.default.trashItem(at: fileURL(for: doc), resultingItemURL: nil)
        load()
    }

    func trash(id: String) throws {
        try ensureUnlocked()
        guard let doc = document(id: id) else { return }
        try trash(filePath: fileURL(for: doc).path)
    }

    private func validateProperties(_ properties: [DocProperty]) throws {
        for prop in properties {
            let trimmed = prop.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if !FrontmatterCodec.isValidPropertyKey(prop.key) {
                throw DocumentStoreError.invalidPropertyKey(key: trimmed)
            }
        }
    }

    /// Case-insensitive substring over title, category, tags, summary and body; snippet around the first body hit; sorted by title.
    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for doc in documents {
            let haystack = "\(doc.title)\n\(doc.category)\n\(doc.tags.joined(separator: " "))\n\(doc.summary)\n\(doc.body)".lowercased()
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
            } else if !doc.summary.isEmpty {
                snippet = doc.summary
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

    /// True when the folder carries the macOS locked flag (`scripts/ops-lock.sh`).
    var isLocked: Bool {
        // FileManager, not URL.resourceValues: URLs cache resource values, and a lock set
        // while the app runs must show up at once.
        (try? FileManager.default.attributesOfItem(atPath: folder.path)[.immutable] as? Bool) == true
    }

    private func ensureUnlocked() throws {
        if isLocked { throw LockedError() }
    }

    private func write(_ doc: OpsDocument, to url: URL) throws {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        let root = folder.standardizedFileURL.path
        guard parent == root, FrontmatterCodec.isValidID(doc.id) else {
            throw DocumentStoreError.invalidDocumentID(id: doc.id)
        }
        let data = Data(FrontmatterCodec.serialize(doc).utf8)
        try data.write(to: url, options: .atomic)
    }
}

/// Thrown when a page change is tried while the folder is locked.
struct LockedError: LocalizedError {
    var errorDescription: String? {
        "The manual is locked, so pages cannot change here. The operator unlocks it with ops-lock unlock (scripts/ops-lock.sh in the app repo)."
    }
}
