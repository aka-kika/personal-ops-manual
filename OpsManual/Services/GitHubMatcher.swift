import Foundation

/// Which repo a page is about, how it is named in lists, and what on the page no
/// longer matches GitHub. Pure functions over the page and the facts.
enum GitHubMatcher {
    static let category = "GitHub"

    /// "Personal Ops Manual (release)" shows as "Personal Ops Manual".
    static func displayTitle(_ title: String) -> String {
        for suffix in [" (release)", " (Release)"] where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count))
        }
        return title
    }

    static func property(_ doc: OpsDocument, _ key: String) -> String? {
        doc.properties.first { $0.key == key }?.value.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    /// The repo the page names: its `repo:` line, else the "Source:" link, else a repo
    /// whose name is the page title (spaces as dashes, any case). "owner/name", or nil.
    static func repoKey(for doc: OpsDocument, known: [String: RemoteRepo], login: String?) -> String? {
        if let repo = property(doc, "repo"), GitHubProbe.isRepoName(repo) { return repo.lowercased() }
        if let source = sourceRepo(in: doc.body) { return source.lowercased() }
        let title = displayTitle(doc.title).lowercased()
        let candidates = [title.replacingOccurrences(of: " ", with: "-"), title.replacingOccurrences(of: " ", with: "")]
        let byName = known.values.filter { repo in
            let name = repo.name.lowercased()
            return candidates.contains(name) && (login == nil || repo.nameWithOwner.lowercased().hasPrefix(login!.lowercased() + "/"))
        }
        return byName.count == 1 ? byName[0].key : nil
    }

    /// "- Source: [aka-kika/personal-ops-manual](https://github.com/aka-kika/personal-ops-manual)".
    static func sourceRepo(in body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.lowercased().hasPrefix("- source:") else { continue }
            if let full = firstGitHubRepo(in: t) { return full }
        }
        return nil
    }

    static func firstGitHubRepo(in text: String) -> String? {
        guard let range = text.range(of: #"github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"#, options: .regularExpression) else { return nil }
        var full = String(text[range].dropFirst("github.com/".count))
        if full.hasSuffix(".git") { full = String(full.dropLast(4)) }
        return GitHubProbe.isRepoName(full) ? full : nil
    }

    /// The release the page claims: a "Latest release" line with a version on it, or
    /// the first version under a "## Latest release" heading.
    static func pageRelease(in body: String) -> String? {
        let lines = body.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.lowercased().contains("latest release") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                for next in lines.dropFirst(i + 1) {
                    let t = next.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { continue }
                    if t.hasPrefix("#") { break }
                    if let v = version(in: t) { return v }
                    break
                }
            } else if let v = version(in: line) {
                return v
            }
        }
        return nil
    }

    static func version(in text: String) -> String? {
        guard let r = text.range(of: #"\bv?\d+\.\d+(\.\d+)?\b"#, options: .regularExpression) else { return nil }
        return String(text[r])
    }

    /// What on a GitHub page no longer matches, as Drift findings (Kika, 2026-11-06:
    /// mismatches show in Drift, not on the repo page). Never edits the page.
    static func findings(for doc: OpsDocument, remote: RemoteRepo?, local: LocalRepo?, remoteKnown: Bool, at date: Date) -> [DriftResult] {
        func result(_ claim: String, _ subject: String, _ says: String, _ now: String, _ status: DriftResult.Status, _ source: String) -> DriftResult {
            DriftResult(pageID: doc.id, pageTitle: doc.title, line: "repo:\(claim)", kind: .repo, claim: claim, subject: subject,
                        pageSays: says, now: now, status: status, source: source, checkedAt: date)
        }
        var out: [DriftResult] = []
        if let remote {
            if let claimed = pageRelease(in: doc.body) {
                if let tag = remote.latestTag {
                    out.append(result("Latest release", remote.nameWithOwner, claimed, tag,
                                      DriftEvaluator.sameVersion(claimed, tag) ? .holds : .drifted, "GitHub \(remote.nameWithOwner)"))
                } else {
                    out.append(result("Latest release", remote.nameWithOwner, claimed, "no release on GitHub", .drifted, "GitHub \(remote.nameWithOwner)"))
                }
            }
            if remote.isArchived, doc.status.lowercased() == "active" {
                out.append(result("Status", remote.nameWithOwner, "active", "archived on GitHub", .drifted, "GitHub \(remote.nameWithOwner)"))
            }
        } else if remoteKnown, let named = property(doc, "repo") {
            out.append(result("Repo", named, "on GitHub", "not found", .drifted, "gh, signed in as the owner"))
        }
        if let local, !local.exists, let path = property(doc, "path") {
            out.append(result("Path", path, "folder on this Mac", "missing", .drifted, "this Mac"))
        }
        return out
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
