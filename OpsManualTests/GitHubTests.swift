import XCTest
@testable import OpsManual

private func page(_ title: String, category: String = "GitHub", body: String = "", properties: [DocProperty] = [], id: String? = nil) -> OpsDocument {
    OpsDocument(id: id ?? title, title: title, category: category, summary: "", tags: [], createdAt: "", updatedAt: "",
                properties: properties + [DocProperty(key: "status", value: "active")], body: body)
}

private func remote(_ full: String, visibility: RemoteRepo.Visibility = .private, tag: String? = nil) -> RemoteRepo {
    RemoteRepo(nameWithOwner: full, name: String(full.split(separator: "/")[1]), visibility: visibility, isArchived: false,
               url: "https://github.com/\(full)", latestTag: tag, openPRs: 0, ci: .success, ciName: "release check", ciAt: nil)
}

final class InboxSyncTests: XCTestCase {
    private let header = InboxReport.header
    private let date = InboxReport.stampFormatter.date(from: "2026-11-06 01:20 UTC")!
    private let later = InboxReport.stampFormatter.date(from: "2026-11-07 01:20 UTC")!

    func testWritesTwoSectionsBeforeTheReadersAndKeepsTheirLines() {
        let old = header + "- [ ] 2026-11-05 22:10 UTC · goose · page: SSH · page says \"x\"; now y · evidence: z\n"
        let gh = [InboxSync.Finding(page: "Feed", what: "page says \"Latest release v1.6.0\"; now v1.6.1", evidence: "GitHub aka-kika/feed-mac")]
        let mac = [InboxSync.Finding(page: "Feed", what: "page says \"Port 4329 node listening\"; now nothing listening", evidence: "lsof")]
        let out = InboxSync.apply(to: old, github: gh, mac: mac, at: date)
        let gIndex = out.range(of: "## Out of date: GitHub")!.lowerBound
        let mIndex = out.range(of: "## Out of date: this Mac")!.lowerBound
        let rIndex = out.range(of: "## From readers")!.lowerBound
        XCTAssertTrue(gIndex < mIndex && mIndex < rIndex)
        XCTAssertTrue(out.hasPrefix("# Reports for the operator"))
        XCTAssertTrue(out[rIndex...].contains("· goose · page: SSH"))
        let reports = InboxReport.parse(out)
        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(reports.filter(\.outOfDate).map(\.agent), ["github", "drift"])
        XCTAssertFalse(reports.contains(where: \.malformed))
        // A reader's report_change append lands under From readers, not inside a section.
        let appended = out + "- [ ] 2026-11-06 02:00 UTC · cursor · page: Git · page says \"a\"; now b\n"
        XCTAssertEqual(InboxReport.parse(appended).last?.outOfDate, false)
    }

    func testOnceEachFixedLinesGoTickedLinesStayAndUnknownSectionsAreUntouched() {
        let f = InboxSync.Finding(page: "Feed", what: "page says \"Latest release v1.6.0\"; now v1.6.1", evidence: "GitHub")
        let first = InboxSync.apply(to: header, github: [f], mac: [], at: date)
        // Same mismatch again: the line stays as it was (same stamp), not added twice.
        let second = InboxSync.apply(to: first, github: [f], mac: [], at: later)
        XCTAssertEqual(second, first)
        // GitHub moved on: same page and claim, new "now": one line, updated.
        let moved = InboxSync.Finding(page: "Feed", what: "page says \"Latest release v1.6.0\"; now v1.7.0", evidence: "GitHub")
        let third = InboxSync.apply(to: second, github: [moved], mac: [], at: later)
        XCTAssertEqual(InboxReport.parse(third).filter(\.outOfDate).map(\.what), [moved.what])
        // GitHub not readable: its section stays exactly as it is.
        XCTAssertEqual(InboxSync.apply(to: third, github: nil, mac: [], at: later), third)
        // The fact holds again: the open line goes away by itself.
        let fixed = InboxSync.apply(to: third, github: [], mac: [], at: later)
        XCTAssertTrue(InboxReport.parse(fixed).filter(\.outOfDate).isEmpty)
        XCTAssertFalse(fixed.contains("## Out of date: GitHub"))
        // A ticked line is the operator's: kept, and not re-added as open.
        let ticked = third.replacingOccurrences(of: "- [ ] 2026-11-07", with: "- [x] 2026-11-07")
        let again = InboxSync.apply(to: ticked, github: [moved], mac: [], at: later)
        XCTAssertEqual(InboxReport.parse(again).filter(\.outOfDate).map(\.handled), [true])
    }

    func testFindingsOnlyFromDriftedResults() {
        let r = DriftResult(pageID: "p", pageTitle: "Feed", line: "port 4329", kind: .port, claim: "Port 4329", subject: "4329",
                            pageSays: "node listening", now: "nothing listening", status: .drifted, source: "lsof", checkedAt: date)
        var holds = r; holds.status = .holds
        var unknown = r; unknown.status = .unknown
        XCTAssertEqual(InboxSync.findings(from: [r, holds, unknown]).map(\.what), ["page says \"Port 4329 node listening\"; now nothing listening"])
    }
}

final class GitHubParsingTests: XCTestCase {
    func testParsesTheOneCallQuery() throws {
        let json = """
        {"data":{"viewer":{"login":"aka-kika","repositories":{"pageInfo":{"hasNextPage":true,"endCursor":"abc"},"nodes":[
        {"nameWithOwner":"aka-kika/personal-ops-manual","name":"personal-ops-manual","visibility":"PUBLIC","isArchived":false,"url":"https://github.com/aka-kika/personal-ops-manual",
         "latestRelease":{"tagName":"v2.3.0"},"refs":{"nodes":[{"name":"v2.3.0"}]},"pullRequests":{"totalCount":1},
         "defaultBranchRef":{"target":{"statusCheckRollup":{"state":"FAILURE"},"checkSuites":{"nodes":[{"updatedAt":"2026-11-06T01:30:58Z","workflowRun":{"workflow":{"name":"release check"}}}]}}}},
        {"nameWithOwner":"aka-kika/feed-mac","name":"feed-mac","visibility":"PRIVATE","isArchived":true,"url":"u",
         "latestRelease":null,"refs":{"nodes":[{"name":"v1.6.1"}]},"pullRequests":{"totalCount":0},"defaultBranchRef":null}
        ]}}}}
        """
        let page = try XCTUnwrap(GitHubProbe.parseViewer(Data(json.utf8)))
        XCTAssertEqual(page.login, "aka-kika")
        XCTAssertEqual(page.next, "abc")
        XCTAssertEqual(page.repos.count, 2)
        XCTAssertEqual(page.repos[0].visibility, .public)
        XCTAssertEqual(page.repos[0].latestTag, "v2.3.0")
        XCTAssertEqual(page.repos[0].ci, .failure)
        XCTAssertEqual(page.repos[0].ciName, "release check")
        XCTAssertEqual(page.repos[0].openPRs, 1)
        // No release page: the newest tag counts.
        XCTAssertEqual(page.repos[1].latestTag, "v1.6.1")
        XCTAssertTrue(page.repos[1].isArchived)
        XCTAssertEqual(page.repos[1].ci, RemoteRepo.CI.none)
    }

    func testPorcelainCountsOnlyTrackedChanges() {
        let out = """
        ## main...origin/main [ahead 1, behind 2]
         M OpsManual/App/AppState.swift
        D  old.swift
        R  a.swift -> b.swift
        ?? IDEAS.md
        """
        let repo = LocalRepo.parse(porcelain: out, path: "~/x")
        XCTAssertEqual(repo.branch, "main")
        XCTAssertEqual(repo.upstream, "origin/main")
        XCTAssertEqual(repo.ahead, 1)
        XCTAssertEqual(repo.behind, 2)
        XCTAssertEqual(repo.changedFiles, ["OpsManual/App/AppState.swift", "old.swift", "b.swift"])
        XCTAssertTrue(repo.hasUnsavedWork)
        let clean = LocalRepo.parse(porcelain: "## main...origin/main\n", path: "~/x")
        XCTAssertFalse(clean.hasUnsavedWork)
        XCTAssertEqual(LocalRepo.parse(porcelain: "## No commits yet on main\n", path: "~/x").branch, "main")
    }

    func testRepoNamesAreCheckedBeforeTheyReachAQuery() {
        XCTAssertTrue(GitHubProbe.isRepoName("aka-kika/personal-ops-manual"))
        XCTAssertFalse(GitHubProbe.isRepoName("aka-kika/x\") { y }"))
        XCTAssertFalse(GitHubProbe.isRepoName("just-a-name"))
        XCTAssertFalse(GitHubProbe.isRepoName("a/b/c"))
    }
}

final class GitHubMatcherTests: XCTestCase {
    private let known = [
        "aka-kika/personal-ops-manual": remote("aka-kika/personal-ops-manual", visibility: .public, tag: "v2.3.0"),
        "aka-kika/feed-mac": remote("aka-kika/feed-mac"),
        "aka-kika/akakika-socials": remote("aka-kika/akakika-socials"),
    ]

    func testNamesWithoutReleaseAndHowAPageNamesItsRepo() {
        XCTAssertEqual(GitHubMatcher.displayTitle("Personal Ops Manual (release)"), "Personal Ops Manual")
        XCTAssertEqual(GitHubMatcher.displayTitle("GitHub index"), "GitHub index")
        // repo: line first.
        XCTAssertEqual(GitHubMatcher.repoKey(for: page("Feed (release)", properties: [DocProperty(key: "repo", value: "aka-kika/feed-mac")]),
                                             known: known, login: "aka-kika"), "aka-kika/feed-mac")
        // Then the Source: link.
        let feed = page("Feed (release)", body: "- Source: [aka-kika/feed-mac](https://github.com/aka-kika/feed-mac)")
        XCTAssertEqual(GitHubMatcher.repoKey(for: feed, known: known, login: "aka-kika"), "aka-kika/feed-mac")
        // Then the title, spaces as dashes.
        XCTAssertEqual(GitHubMatcher.repoKey(for: page("Akakika Socials (release)"), known: known, login: "aka-kika"), "aka-kika/akakika-socials")
        XCTAssertNil(GitHubMatcher.repoKey(for: page("Homebrew taps"), known: known, login: "aka-kika"))
    }

    func testPageReleaseLineOrHeading() {
        XCTAssertEqual(GitHubMatcher.pageRelease(in: "- Latest release page: [v2.2.4](https://x/releases/tag/v2.2.4)"), "v2.2.4")
        XCTAssertEqual(GitHubMatcher.pageRelease(in: "## Latest release\n\n2.2.4 (build 9) on 2026-10-16: icons"), "2.2.4")
        XCTAssertNil(GitHubMatcher.pageRelease(in: "## Latest release\n\nNone yet."))
    }

    func testFindingsGoToDriftNotToThePage() {
        let doc = page("Personal Ops Manual (release)", body: "- Latest release page: [v2.2.4](x)",
                       properties: [DocProperty(key: "path", value: "~/nowhere")])
        let results = GitHubMatcher.findings(for: doc, remote: known["aka-kika/personal-ops-manual"], local: .missing("~/nowhere"),
                                             remoteKnown: true, at: Date())
        XCTAssertEqual(results.map(\.claim), ["Latest release", "Path"])
        XCTAssertEqual(results[0].status, .drifted)
        XCTAssertEqual(results[0].reportWhat, "page says \"Latest release v2.2.4\"; now v2.3.0")
        XCTAssertEqual(results[0].kind, .repo)
        // A repo: line GitHub doesn't know, only when GitHub could be read.
        let gone = page("Gone", properties: [DocProperty(key: "repo", value: "aka-kika/gone")])
        XCTAssertEqual(GitHubMatcher.findings(for: gone, remote: nil, local: nil, remoteKnown: true, at: Date()).map(\.now), ["not found"])
        XCTAssertTrue(GitHubMatcher.findings(for: gone, remote: nil, local: nil, remoteKnown: false, at: Date()).isEmpty)
        // `repo` is never a checks: line.
        XCTAssertEqual(DriftCheck.parse("repo aka-kika/x"), .failure(.unknownKind("repo")))
    }
}

@MainActor
final class GitHubMonitorTests: XCTestCase {
    private struct FakeGitHub: GitHubProbing {
        var result: Result<(login: String, repos: [RemoteRepo]), GitHubProbeError>
        func repos(extra: [String]) -> Result<(login: String, repos: [RemoteRepo]), GitHubProbeError> { result }
        func local(path: String) -> LocalRepo {
            LocalRepo(path: path, exists: true, isRepo: true, branch: "main", upstream: "origin/main", ahead: 1, behind: 0, changedFiles: ["a.swift"])
        }
    }

    func testKeepsOnlyReposAPageNamesAndCountsUnsavedWorkWithAPath() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ops-github-\(UUID().uuidString)"))
        let repos = [remote("aka-kika/personal-ops-manual", visibility: .public), remote("aka-kika/unrelated-private-thing")]
        let monitor = GitHubMonitor(defaults: defaults, probe: FakeGitHub(result: .success(("aka-kika", repos))))
        let withPath = page("Personal Ops Manual (release)", properties: [DocProperty(key: "path", value: "~/x")], id: "a")
        let noPath = page("Feed (release)", id: "b")
        await monitor.refresh([withPath, noPath])
        XCTAssertEqual(Array(monitor.snapshot.remote.keys), ["aka-kika/personal-ops-manual"])
        XCTAssertTrue(monitor.hasUnsavedWork(withPath))
        XCTAssertEqual(monitor.unsavedRepoPages(in: [withPath, noPath]).map(\.id), ["a"])
        // It comes back after a restart.
        XCTAssertEqual(GitHubMonitor(defaults: defaults, probe: FakeGitHub(result: .failure(.ghMissing))).snapshot.remote.count, 1)
    }

    func testSignedOutKeepsLocalStateAndSaysWhy() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ops-github-\(UUID().uuidString)"))
        let monitor = GitHubMonitor(defaults: defaults, probe: FakeGitHub(result: .failure(.notSignedIn)))
        let doc = page("X", properties: [DocProperty(key: "path", value: "~/x")], id: "a")
        await monitor.refresh([doc])
        XCTAssertEqual(monitor.snapshot.remoteError, "gh is not signed in")
        XCTAssertFalse(monitor.remoteKnown)
        XCTAssertTrue(monitor.hasUnsavedWork(doc))
    }
}

final class PageLinksTests: XCTestCase {
    func testOneLinkByCategory() {
        let mcp = page("feed (MCP)", category: "MCP (third-party)", body: "Source: https://github.com/someone/feed-mcp and more")
        XCTAssertEqual(PageLinks.link(for: mcp), .repo(URL(string: "https://github.com/someone/feed-mcp")!))
        let gh = page("Sift (release)", properties: [DocProperty(key: "repo", value: "aka-kika/sift")])
        XCTAssertEqual(PageLinks.link(for: gh), .repo(URL(string: "https://github.com/aka-kika/sift")!))
        let account = page("Vercel", category: "Accounts", properties: [DocProperty(key: "url", value: "https://vercel.com/dashboard")])
        XCTAssertEqual(PageLinks.link(for: account), .site(URL(string: "https://vercel.com/dashboard")!))
        let domain = page("akakika.com", category: "Domains", body: "Live at [akakika.com](https://akakika.com).")
        XCTAssertEqual(PageLinks.link(for: domain), .site(URL(string: "https://akakika.com")!))
        XCTAssertNil(PageLinks.link(for: page("Feed", category: "Services", body: "https://x.com")))
        XCTAssertNil(PageLinks.link(for: page("No link", category: "CLI tools")))
    }
}

@MainActor
final class MCPRowTests: XCTestCase {
    func testOneRowShowsBothMCPCategories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ops-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (id, title, category) in [("m1", "recall (MCP)", "MCP (mine)"), ("m2", "firecrawl", "MCP (third-party)"), ("s1", "Feed", "Services")] {
            let text = "---\ntitle: \(title)\ncategory: \(category)\ntags:\n  []\ncreatedAt: 2026-09-13T13:30:00.000Z\nupdatedAt: 2026-09-13T13:30:00.000Z\nid: \(id)\n---\n\nBody.\n"
            try text.write(to: dir.appendingPathComponent("\(id).md"), atomically: true, encoding: .utf8)
        }
        let store = DocumentStore(folder: dir, watch: false)
        let state = AppState()
        state.select(.mcp)
        XCTAssertEqual(Set(state.visibleDocuments(in: store).map(\.id)), ["m1", "m2"])
        XCTAssertEqual(state.listTitle, "MCP")
    }
}

final class InboxSectionsTests: XCTestCase {
    func testAMissingFolderIsAFactAboutThisMac() {
        let at = Date()
        let path = DriftResult(pageID: "r", pageTitle: "Gone", line: "repo:Path", kind: .repo, claim: "Path", subject: "~/x",
                               pageSays: "folder on this Mac", now: "missing", status: .drifted, source: "this Mac", checkedAt: at)
        var release = path; release.claim = "Latest release"; release.pageSays = "v1"; release.now = "v2"
        let sections = InboxSync.sections(checks: [], repo: [path, release], githubRead: false)
        XCTAssertNil(sections.github)
        XCTAssertEqual(sections.mac.count, 1)
        XCTAssertEqual(InboxSync.sections(checks: [], repo: [path, release], githubRead: true).github?.count, 1)
    }
}
