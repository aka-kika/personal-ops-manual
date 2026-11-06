import Foundation

/// Writes what is out of date into the inbox by itself, for the operator (Kika,
/// 2026-11-06: "i almost never open the ops app. it should be in inbox under a github
/// section, not mixed with rest"). The file keeps its header, then two machine-written
/// sections, then the readers' reports:
///
///     # Reports for the operator
///     ...header...
///
///     ## Out of date: GitHub
///     - [ ] 2026-11-06 01:20 UTC · github · page: Feed · page says "Latest release v1.6.0"; now v1.6.1 · evidence: ...
///
///     ## Out of date: this Mac
///     - [ ] 2026-11-06 01:20 UTC · drift · page: Feed · page says "Port 4329 node listening"; now nothing listening · evidence: ...
///
///     ## From readers
///     - [ ] ... (report_change lines; new ones are appended at the end, so they land here)
///
/// Every line has the report_change shape, so list_reports reads them unchanged.
/// One line per page and claim: a line that still applies stays as it is, one whose
/// fact holds again is removed, a new mismatch is added once. Ticked lines are left
/// for the operator. The readers' lines are never changed.
enum InboxSync {
    enum Section: String, CaseIterable, Sendable {
        case github = "## Out of date: GitHub"
        case mac = "## Out of date: this Mac"

        var agent: String {
            switch self {
            case .github: "github"
            case .mac: "drift"
            }
        }
    }

    static let readersHeading = "## From readers"

    struct Finding: Hashable, Sendable {
        var page: String
        var what: String
        var evidence: String
    }

    /// A repo folder missing on this Mac is a fact about the Mac, so it goes in that
    /// section, even when GitHub could not be read.
    static func isMacFact(_ result: DriftResult) -> Bool { result.kind != .repo || result.claim == "Path" }

    /// The two sections from the checks: results and the GitHub results.
    static func sections(checks: [DriftResult], repo: [DriftResult], githubRead: Bool) -> (github: [Finding]?, mac: [Finding]) {
        let github = githubRead ? findings(from: repo.filter { !isMacFact($0) }) : nil
        return (github, findings(from: checks + repo.filter(isMacFact)))
    }

    static func findings(from results: [DriftResult]) -> [Finding] {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        return results.filter { $0.status == .drifted }.map {
            Finding(page: $0.pageTitle, what: $0.reportWhat, evidence: "\($0.source), checked \(time.string(from: $0.checkedAt))")
        }
    }

    /// The same page and claim: the part before "; now".
    static func key(page: String, what: String) -> String {
        let claim = what.components(separatedBy: "; now").first ?? what
        return InboxReport.oneLine(page).lowercased() + "|" + InboxReport.oneLine(claim)
    }

    /// The new file text. A section passed as nil is left exactly as it is (its check
    /// could not run, so nothing in it can be called fixed).
    static func apply(to text: String, github: [Finding]?, mac: [Finding]?, at date: Date = Date()) -> String {
        let lines = text.isEmpty ? InboxReport.header.components(separatedBy: "\n") : text.components(separatedBy: "\n")
        var header: [String] = []
        var existing: [Section: [String]] = [:]
        var readers: [String] = []
        var current: Section?
        var inReaders = false
        var seenBody = false
        for line in lines {
            if let section = Section(rawValue: line.trimmingCharacters(in: .whitespaces)) {
                current = section; inReaders = false; seenBody = true
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == readersHeading {
                current = nil; inReaders = true; seenBody = true
                continue
            }
            if let section = current {
                if line.hasPrefix("## ") { current = nil; inReaders = true; readers.append(line) }
                else if !line.trimmingCharacters(in: .whitespaces).isEmpty { existing[section, default: []].append(line) }
                continue
            }
            if inReaders { readers.append(line); continue }
            // Before any section: the header ends at the first report line.
            if !seenBody, !line.hasPrefix("- [") { header.append(line); continue }
            seenBody = true
            inReaders = true
            readers.append(line)
        }

        func merged(_ section: Section, _ fresh: [Finding]?) -> [String] {
            let old = existing[section] ?? []
            guard let fresh else { return old }
            let wanted = Dictionary(fresh.map { (key(page: $0.page, what: $0.what), $0) }, uniquingKeysWith: { a, _ in a })
            var out: [String] = []
            var covered = Set<String>()
            for line in old {
                guard let report = InboxReport.parse(line).first, !report.malformed else { out.append(line); continue }
                let k = key(page: report.page, what: report.what)
                if report.handled {
                    out.append(line); covered.insert(k)          // the operator ticked it: theirs to delete
                } else if let finding = wanted[k], !covered.contains(k) {
                    covered.insert(k)
                    out.append(report.what == InboxReport.oneLine(finding.what) ? line
                               : InboxReport.line(agent: section.agent, page: finding.page, what: finding.what, evidence: finding.evidence, at: date))
                }
                // An open line whose fact holds again is dropped.
            }
            for finding in fresh {
                let k = key(page: finding.page, what: finding.what)
                guard !covered.contains(k) else { continue }
                covered.insert(k)
                out.append(InboxReport.line(agent: section.agent, page: finding.page, what: finding.what, evidence: finding.evidence, at: date))
            }
            return out
        }

        let gh = merged(.github, github)
        let mc = merged(.mac, mac)
        var out = header
        while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty { out.removeLast() }
        out.append("")
        if !gh.isEmpty { out += [Section.github.rawValue] + gh + [""] }
        if !mc.isEmpty { out += [Section.mac.rawValue] + mc + [""] }
        var body = readers
        while let first = body.first, first.trimmingCharacters(in: .whitespaces).isEmpty { body.removeFirst() }
        while let last = body.last, last.trimmingCharacters(in: .whitespaces).isEmpty { body.removeLast() }
        out.append(readersHeading)
        out += body
        return out.joined(separator: "\n") + "\n"
    }

    /// Reads, merges and writes the inbox in one step. Returns the open lines per section.
    @discardableResult
    static func write(github: [Finding]?, mac: [Finding]?, inboxURL: URL, at date: Date = Date()) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = (try? String(contentsOf: inboxURL, encoding: .utf8)) ?? ""
        let new = apply(to: old, github: github, mac: mac, at: date)
        if new != old { try new.write(to: inboxURL, atomically: true, encoding: .utf8) }
        return new
    }
}
