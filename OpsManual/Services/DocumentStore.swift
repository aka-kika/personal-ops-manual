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

/// The folder is the source of truth. The store reads every `.md` with an `id` and
/// reloads when the folder changes. Since 2.4.0 the app only reads: pages change
/// through the operator, and the only write is a Report/Send line in the inbox.
@MainActor
@Observable
final class DocumentStore {
    private(set) var folder: URL
    private(set) var documents: [OpsDocument] = []
    private(set) var loadError: String?
    /// Every checkbox line in `_inbox/reports.md`: the reports readers filed through the MCP.
    private(set) var inboxReports: [InboxReport] = []
    /// Open lines in the inbox.
    var inboxOpenCount: Int { inboxReports.filter { !$0.handled }.count }
    var openInboxReports: [InboxReport] { inboxReports.filter { !$0.handled } }
    @ObservationIgnored private var inboxWatcher: FolderWatcher?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private let shouldWatch: Bool

    init(folder: URL, watch: Bool = true) {
        self.folder = folder
        self.shouldWatch = watch
        load()
        startWatching()
    }

    /// Pages that are not parked or archived: what the category lists show.
    var activeDocuments: [OpsDocument] { documents.filter { !$0.isParked } }
    var parkedDocuments: [OpsDocument] { documents.filter(\.isParked) }

    var categories: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        // A category's overview page is not one of its pages (it shows as the list's footer).
        for doc in activeDocuments where !CategoryOverviewPage.isOverview(doc) { counts[doc.category, default: 0] += 1 }
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
            inboxReports = readInbox()
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

    private func readInbox() -> [InboxReport] {
        guard let raw = try? String(contentsOf: inboxFileURL, encoding: .utf8) else { return [] }
        return InboxReport.parse(raw)
    }

    /// The page a report names: by id first, then by title (case-insensitive).
    func document(forReportPage page: String) -> OpsDocument? {
        let key = page.trimmingCharacters(in: .whitespaces)
        if let doc = document(id: key) { return doc }
        return documents.first { $0.title.caseInsensitiveCompare(key) == .orderedSame }
    }

    private func startWatching() {
        guard shouldWatch else { watcher = nil; inboxWatcher = nil; return }
        let inboxDir = folder.appendingPathComponent(Self.inboxFolderName)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        inboxWatcher = FolderWatcher(url: inboxDir) { [weak self] in self?.load() }
        watcher = FolderWatcher(url: folder) { [weak self] in self?.load() }
    }

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

}
