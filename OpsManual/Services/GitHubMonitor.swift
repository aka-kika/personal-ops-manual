import Foundation
import Observation

/// What the GitHub category shows: GitHub facts (through `gh`) and each page's working
/// copy (local git), refreshed on the same interval as Drift and from the GitHub row's
/// Refresh. Nothing is written; mismatches go to Drift, where Report files them.
@MainActor
@Observable
final class GitHubMonitor {
    private(set) var snapshot = GitHubSnapshot()
    private(set) var isRefreshing = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let probe: any GitHubProbing
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, probe: any GitHubProbing = GitHubProbe()) {
        self.defaults = defaults
        self.probe = probe
        restore()
    }

    // MARK: What the views read

    struct Info: Sendable {
        var key: String?
        var remote: RemoteRepo?
        var local: LocalRepo?
    }

    func info(for doc: OpsDocument) -> Info { Self.info(for: doc, in: snapshot) }

    nonisolated static func info(for doc: OpsDocument, in snapshot: GitHubSnapshot) -> Info {
        let key = GitHubMatcher.repoKey(for: doc, known: snapshot.remote, login: snapshot.login)
        return Info(key: key, remote: key.flatMap { snapshot.remote[$0] }, local: snapshot.local[doc.id])
    }

    /// Something on this Mac is not saved yet: tracked changes not committed, or commits not pushed.
    func hasUnsavedWork(_ doc: OpsDocument) -> Bool { snapshot.local[doc.id]?.hasUnsavedWork ?? false }

    /// For Drift: repos whose page has a `path:` line and that have work not saved yet.
    func unsavedRepoPages(in docs: [OpsDocument]) -> [OpsDocument] {
        docs.filter { GitHubMatcher.property($0, "path") != nil && hasUnsavedWork($0) }
    }

    var remoteKnown: Bool { Self.remoteKnown(snapshot) }

    nonisolated static func remoteKnown(_ snapshot: GitHubSnapshot) -> Bool { snapshot.remoteError == nil && !snapshot.remote.isEmpty }

    // MARK: Refreshing

    nonisolated static func pages(from documents: [OpsDocument]) -> [OpsDocument] {
        documents.filter { $0.category == GitHubMatcher.category && !$0.isParked }
    }

    func refresh(_ documents: [OpsDocument]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let probe = self.probe
        let previous = snapshot
        snapshot = await Task.detached(priority: .utility) {
            Self.collect(documents: documents, previous: previous, probe: probe)
        }.value
        isRefreshing = false
        save()
    }

    /// One refresh, without the app's window: also used by `--check`.
    nonisolated static func collect(documents: [OpsDocument], previous: GitHubSnapshot, probe: some GitHubProbing, at date: Date = Date()) -> GitHubSnapshot {
        let pages = Self.pages(from: documents)
        let named = pages.compactMap { GitHubMatcher.property($0, "repo") }.filter(GitHubProbe.isRepoName)
            + pages.compactMap { GitHubMatcher.sourceRepo(in: $0.body) }
        var locals: [String: LocalRepo] = [:]
        for doc in pages {
            if let path = GitHubMatcher.property(doc, "path") { locals[doc.id] = probe.local(path: path) }
        }
        var next = GitHubSnapshot(remote: previous.remote, local: locals, login: previous.login, refreshedAt: date)
        switch probe.repos(extra: Array(Set(named))) {
        case .success(let result):
            let all = Dictionary(result.repos.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            // Keep only the repos a page names: nothing else is stored.
            var kept: [String: RemoteRepo] = [:]
            for doc in pages {
                if let key = GitHubMatcher.repoKey(for: doc, known: all, login: result.login), let repo = all[key] { kept[key] = repo }
            }
            next.remote = kept
            next.login = result.login
            next.remoteError = nil
        case .failure(let error):
            next.remoteError = error.message
        }
        return next
    }

    func startSchedule(documents: @escaping @MainActor () -> [OpsDocument], interval: @escaping @MainActor () -> DriftInterval) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if interval().isDue(lastChecked: self.snapshot.refreshedAt) { await self.refresh(documents()) }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: Drift findings

    /// The GitHub pages' mismatches, for Drift.
    func driftResults(for documents: [OpsDocument]) -> [DriftResult] { Self.driftResults(for: documents, in: snapshot) }

    nonisolated static func driftResults(for documents: [OpsDocument], in snapshot: GitHubSnapshot) -> [DriftResult] {
        let at = snapshot.refreshedAt ?? Date()
        let known = remoteKnown(snapshot)
        return pages(from: documents).flatMap { doc in
            let info = info(for: doc, in: snapshot)
            return GitHubMatcher.findings(for: doc, remote: info.remote, local: info.local, remoteKnown: known, at: at)
        }
    }

    // MARK: Keeping the last refresh

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: AppSettings.githubSnapshotKey) }
    }

    private func restore() {
        guard let data = defaults.data(forKey: AppSettings.githubSnapshotKey),
              let saved = try? JSONDecoder().decode(GitHubSnapshot.self, from: data) else { return }
        snapshot = saved
    }
}
