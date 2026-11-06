import Foundation
import Observation

/// Runs the Drift checks and keeps the last results, so the sidebar count is there
/// at launch. Checks when Drift opens, on "Check now", and by itself at the interval
/// set in Settings (once a day by default). Never edits a page: Report appends one
/// line to the inbox, the way `report_change` does.
struct DriftPageGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var results: [DriftResult]
}

@MainActor
@Observable
final class DriftMonitor {
    private(set) var results: [DriftResult] = []
    private(set) var lastChecked: Date?
    private(set) var isChecking = false
    /// How long the last check took, for the overview.
    private(set) var lastDuration: TimeInterval?
    private(set) var reportError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let probe: any DriftProbing
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Where the pages come from when the timer fires.
    @ObservationIgnored private var pagesProvider: (@MainActor () -> [DriftEvaluator.Page])?

    static let agentName = "drift"

    init(defaults: UserDefaults = .standard, probe: any DriftProbing = DriftProbe()) {
        self.defaults = defaults
        self.probe = probe
        restore()
    }

    // MARK: What the views read

    var drifted: [DriftResult] {
        results.filter { $0.status == .drifted }
            .sorted { ($0.driftedSince ?? .distantPast) > ($1.driftedSince ?? .distantPast) || (($0.driftedSince == $1.driftedSince) && $0.pageTitle < $1.pageTitle) }
    }

    /// Pages with at least one drifted claim, newest drift first.
    var driftedPages: [DriftPageGroup] {
        var order: [String] = []
        var byPage: [String: [DriftResult]] = [:]
        for r in drifted {
            if byPage[r.pageID] == nil { order.append(r.pageID) }
            byPage[r.pageID, default: []].append(r)
        }
        return order.map { DriftPageGroup(id: $0, title: byPage[$0]![0].pageTitle, results: byPage[$0]!) }
    }

    var holdsCount: Int { results.filter { $0.status == .holds }.count }
    var driftedCount: Int { results.filter { $0.status == .drifted }.count }
    var unknown: [DriftResult] { results.filter { $0.status == .unknown } }
    var checkedPageCount: Int { Set(results.map(\.pageID)).count }

    func results(forPage id: String) -> [DriftResult] { results.filter { $0.pageID == id } }

    /// Whether an open inbox line already reports this claim.
    func isReported(_ result: DriftResult, in reports: [InboxReport]) -> Bool {
        reports.contains { !$0.handled && $0.page == InboxReport.oneLine(result.pageTitle) && $0.what == InboxReport.oneLine(result.reportWhat) }
    }

    func reportDate(_ result: DriftResult, in reports: [InboxReport]) -> Date? {
        reports.first { !$0.handled && $0.page == InboxReport.oneLine(result.pageTitle) && $0.what == InboxReport.oneLine(result.reportWhat) }?.reportedDate
    }

    // MARK: Checking

    static func pages(from documents: [OpsDocument]) -> [DriftEvaluator.Page] {
        documents.filter { !$0.checks.isEmpty && !$0.isParked }.map { .init(id: $0.id, title: $0.title, checks: $0.checks) }
    }

    func check(_ pages: [DriftEvaluator.Page]) async {
        guard !isChecking else { return }
        isChecking = true
        let started = Date()
        let probe = self.probe
        let fresh = await Task.detached(priority: .utility) {
            DriftEvaluator.evaluate(pages: pages, probe: probe, now: started)
        }.value
        results = DriftEvaluator.carryOver(fresh, from: results)
        lastChecked = started
        lastDuration = Date().timeIntervalSince(started)
        isChecking = false
        save()
    }

    /// Starts the background check loop. It looks once a minute whether a check is due,
    /// so a changed interval in Settings takes effect without a restart.
    func startSchedule(pages: @escaping @MainActor () -> [DriftEvaluator.Page]) {
        pagesProvider = pages
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.interval.isDue(lastChecked: self.lastChecked), let provider = self.pagesProvider {
                    await self.check(provider())
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    var interval: DriftInterval {
        DriftInterval.fromStored(defaults.object(forKey: AppSettings.driftIntervalKey) as? Int ?? DriftInterval.default.rawValue)
    }

    // MARK: Report

    /// Appends one report line to `_inbox/reports.md`. Returns false and sets `reportError` when it cannot.
    @discardableResult
    func report(_ result: DriftResult, inboxURL: URL, at date: Date = Date()) -> Bool {
        let time = Self.timeFormatter.string(from: result.checkedAt)
        let line = InboxReport.line(agent: Self.agentName, page: result.pageTitle, what: result.reportWhat,
                                    evidence: "\(result.source), checked \(time)", at: date)
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: inboxURL.path) {
                try InboxReport.header.write(to: inboxURL, atomically: true, encoding: .utf8)
            }
            // Start on a fresh line if the file does not end with one.
            let existing = try Data(contentsOf: inboxURL)
            var text = line + "\n"
            if let last = existing.last, last != UInt8(ascii: "\n") { text = "\n" + text }
            let handle = try FileHandle(forWritingTo: inboxURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            reportError = nil
            return true
        } catch {
            reportError = "The report could not be filed: \(error.localizedDescription) The inbox folder may be locked; ops-lock lock opens it again."
            return false
        }
    }

    func clearReportError() { reportError = nil }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: Keeping the last check

    private struct Saved: Codable {
        var results: [DriftResult]
        var lastChecked: Date?
        var duration: TimeInterval?
    }

    private func save() {
        let saved = Saved(results: results, lastChecked: lastChecked, duration: lastDuration)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: AppSettings.driftResultsKey) }
    }

    private func restore() {
        guard let data = defaults.data(forKey: AppSettings.driftResultsKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        results = saved.results
        lastChecked = saved.lastChecked
        lastDuration = saved.duration
    }

    /// Results of pages that no longer exist, or no longer state checks, drop out
    /// when the folder changes, so the count never points at nothing.
    func prune(keeping pageIDs: Set<String>) {
        let kept = results.filter { pageIDs.contains($0.pageID) }
        if kept.count != results.count { results = kept; save() }
    }
}
