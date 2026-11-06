import Foundation

/// `Personal Ops Manual --check` (or `opsmanual check`): the daily check without the
/// window, for the operator's run and the weekly maintenance (Kika, 2026-11-06: "i
/// almost never open the ops app"). Runs the pages' checks: lines and the GitHub
/// refresh, writes what is out of date into the inbox's two sections, prints a short
/// summary and exits. Never edits a page.
enum HeadlessCheck {
    static var isRequested: Bool {
        let args = CommandLine.arguments.dropFirst()
        return args.contains("--check") || args.first == "check"
    }

    @MainActor
    static func run() -> Int32 {
        let store = DocumentStore(folder: AppSettings.documentsURL, watch: false)
        if let error = store.loadError {
            FileHandle.standardError.write(Data("opsmanual: cannot read the pages: \(error)\n".utf8))
            return 1
        }
        let docs = store.documents
        let now = Date()
        let mac = DriftEvaluator.evaluate(pages: DriftMonitor.pages(from: docs), probe: DriftProbe(), now: now)
        let snapshot = GitHubMonitor.collect(documents: docs, previous: GitHubSnapshot(), probe: GitHubProbe(), at: now)
        let repo = GitHubMonitor.driftResults(for: docs, in: snapshot)
        let sections = InboxSync.sections(checks: mac, repo: repo, githubRead: snapshot.remoteError == nil)
        do {
            try InboxSync.write(github: sections.github, mac: sections.mac, inboxURL: store.inboxFileURL, at: now)
        } catch {
            FileHandle.standardError.write(Data("opsmanual: \(InboxReport.appendFailure(error))\n".utf8))
            return 1
        }
        let open = InboxReport.parse((try? String(contentsOf: store.inboxFileURL, encoding: .utf8)) ?? "")
            .filter { !$0.handled && $0.outOfDate }.count
        var lines = [
            "Checked \(Set(mac.map(\.pageID)).count) pages with checks: \(mac.filter { $0.status == .drifted }.count) out of date, \(mac.filter { $0.status == .unknown }.count) could not run.",
        ]
        if let error = snapshot.remoteError {
            lines.append("GitHub: not checked (\(error)); its inbox section was left as it was. Local folders were checked.")
        } else {
            lines.append("GitHub: \(snapshot.remote.count) repos, \(repo.filter { $0.status == .drifted }.count) out of date.")
        }
        lines.append("Inbox: \(open) open out-of-date lines in \(store.inboxFileURL.path)")
        print(lines.joined(separator: "\n"))
        return 0
    }
}
