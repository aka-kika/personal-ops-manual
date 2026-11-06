import XCTest
@testable import OpsManual

/// A Mac made of fixed answers.
private struct FakeProbe: DriftProbing {
    var apps: [String: DriftFacts.App] = [:]
    var notarized: DriftFacts.Notarization = .notarized("Notarized Developer ID")
    var servers: [String: String]? = ["personal-ops-manual": "user"]
    var ports: [Int: DriftFacts.Port] = [:]
    var jobs: [String: DriftFacts.Launchd] = [:]
    var clis: [String: DriftFacts.CLI] = [:]

    func app(_ subject: String) -> DriftFacts.App { apps[subject] ?? .missing(path: "/Applications/\(subject).app") }
    func notarization(path: String) -> DriftFacts.Notarization { notarized }
    func mcpServers() -> [String: String]? { servers }
    func listeners(port: Int) -> DriftFacts.Port { ports[port] ?? .nothing }
    func launchd(label: String) -> DriftFacts.Launchd { jobs[label] ?? .notLoaded }
    func cli(_ name: String) -> DriftFacts.CLI { clis[name] ?? .notFound }
}

final class DriftCheckTests: XCTestCase {
    func testParsesEachKind() throws {
        let app = try DriftCheck.parse(#"app "Personal Ops Manual" 2.2.5 notarized"#).get()
        XCTAssertEqual(app.kind, .app)
        XCTAssertEqual(app.subject, "Personal Ops Manual")
        XCTAssertEqual(app.expected, "2.2.5")
        XCTAssertTrue(app.wantsNotarized)

        let port = try DriftCheck.parse("port 4319 node").get()
        XCTAssertEqual(port.subject, "4319")
        XCTAssertEqual(port.expected, "node")

        let job = try DriftCheck.parse("launchd com.akakika.socials running").get()
        XCTAssertTrue(job.wantsRunning)

        let cli = try DriftCheck.parse("cli gh 2.103.3").get()
        XCTAssertEqual(cli.expected, "2.103.3")

        XCTAssertEqual(try DriftCheck.parse("mcp the-board").get().subject, "the-board")
    }

    func testRejectsWhatItCannotCheckSafely() {
        XCTAssertEqual(DriftCheck.parse("ftp server"), .failure(.unknownKind("ftp")))
        XCTAssertEqual(DriftCheck.parse("port 99999"), .failure(.badPort("99999")))
        XCTAssertEqual(DriftCheck.parse("port"), .failure(.missingSubject))
        // A CLI is a plain name, never a path or a shell word.
        XCTAssertEqual(DriftCheck.parse("cli /bin/rm"), .failure(.badName("/bin/rm")))
        XCTAssertEqual(DriftCheck.parse("cli $(whoami)"), .failure(.badName("$(whoami)")))
        XCTAssertEqual(DriftCheck.parse("cli -rf"), .failure(.badName("-rf")))
        XCTAssertEqual(DriftCheck.parse(#"app "Open"#), .failure(.unclosedQuote))
    }

    func testFirstVersionInOutput() {
        XCTAssertEqual(DriftProbe.firstVersion(in: "gh version 2.103.3 (2026-10-26)\nhttps://x"), "2.103.3")
        XCTAssertEqual(DriftProbe.firstVersion(in: "git version 2.50.1 (Apple Git-155)"), "2.50.1")
        XCTAssertEqual(DriftProbe.firstVersion(in: "v1.2.3-beta.1"), "1.2.3-beta.1")
        XCTAssertNil(DriftProbe.firstVersion(in: "no numbers"))
    }
}

final class DriftEvaluatorTests: XCTestCase {
    private func page(_ checks: [String]) -> DriftEvaluator.Page { .init(id: "p1", title: "Personal Ops Manual", checks: checks) }

    func testAppVersionDriftAndNotarized() {
        var probe = FakeProbe()
        probe.apps["Personal Ops Manual"] = .installed(path: "/Applications/Personal Ops Manual.app", version: "2.2.5")
        let results = DriftEvaluator.evaluate(pages: [page([#"app "Personal Ops Manual" 2.2.4 notarized"#])], probe: probe)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].status, .drifted)
        XCTAssertEqual(results[0].pageSays, "2.2.4")
        XCTAssertEqual(results[0].now, "2.2.5")
        XCTAssertEqual(results[0].reportWhat, "page says \"App version 2.2.4\"; now 2.2.5")
        XCTAssertEqual(results[1].claim, "Notarized")
        XCTAssertEqual(results[1].status, .holds)
    }

    func testTrailingZerosAreTheSameVersion() {
        XCTAssertTrue(DriftEvaluator.sameVersion("1.0", "v1.0.0"))
        XCTAssertTrue(DriftEvaluator.sameVersion("2", "2.0"))
        XCTAssertFalse(DriftEvaluator.sameVersion("1.0", "1.0.1"))
        XCTAssertFalse(DriftEvaluator.sameVersion("1.10", "1.1"))
        XCTAssertFalse(DriftEvaluator.sameVersion("1.0.0-beta", "1.0"))
    }

    func testVersionsMatchWithOrWithoutV() {
        var probe = FakeProbe()
        probe.clis["gh"] = .found(path: "/opt/homebrew/bin/gh", version: "2.103.3")
        let results = DriftEvaluator.evaluate(pages: [page(["cli gh v2.103.3"])], probe: probe)
        XCTAssertEqual(results.map(\.status), [.holds])
    }

    func testMissingThingsAreDriftButUnreadableOnesAreNot() {
        var probe = FakeProbe()
        probe.servers = ["other": "user"]
        probe.ports[4319] = .listening(["node"])
        probe.ports[6464] = .unknown("lsof did not answer")
        let results = DriftEvaluator.evaluate(pages: [page([
            "mcp personal-ops-manual", "port 4319 bun", "port 6464", "launchd com.example.gone", "cli xcodegen", "nonsense line",
        ])], probe: probe)
        XCTAssertEqual(results.map(\.status), [.drifted, .drifted, .unknown, .drifted, .unknown, .unknown])
        XCTAssertEqual(results[0].now, "missing")
        XCTAssertEqual(results[1].now, "node listening")
        XCTAssertEqual(results[3].now, "not loaded")
        XCTAssertEqual(results[4].now, "not on PATH")
    }

    func testPortProcessMatchesShortenedNames() {
        var probe = FakeProbe()
        probe.ports[19222] = .listening(["codync-ho"])
        let results = DriftEvaluator.evaluate(pages: [page(["port 19222 codync-host"])], probe: probe)
        XCTAssertEqual(results.first?.status, .holds)
    }

    func testLaunchdRunningOnlyWhenAskedFor() {
        var probe = FakeProbe()
        probe.jobs["a"] = .loaded(running: false)
        let results = DriftEvaluator.evaluate(pages: [page(["launchd a", "launchd a running"])], probe: probe)
        XCTAssertEqual(results.map(\.status), [.holds, .drifted])
    }

    func testDriftedSinceIsKeptAcrossChecks() {
        var probe = FakeProbe()
        probe.apps["X"] = .installed(path: "/Applications/X.app", version: "2")
        let first = DriftEvaluator.carryOver(
            DriftEvaluator.evaluate(pages: [page(["app X 1"])], probe: probe, now: Date(timeIntervalSince1970: 100)), from: [])
        XCTAssertEqual(first[0].driftedSince, Date(timeIntervalSince1970: 100))
        let second = DriftEvaluator.carryOver(
            DriftEvaluator.evaluate(pages: [page(["app X 1"])], probe: probe, now: Date(timeIntervalSince1970: 500)), from: first)
        XCTAssertEqual(second[0].driftedSince, Date(timeIntervalSince1970: 100))
    }
}

@MainActor
final class DriftMonitorTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "ops-drift-\(UUID().uuidString)"))
    }

    func testCheckKeepsResultsAcrossLaunches() async throws {
        let defaults = try makeDefaults()
        var probe = FakeProbe()
        probe.apps["X"] = .installed(path: "/Applications/X.app", version: "2")
        let monitor = DriftMonitor(defaults: defaults, probe: probe)
        await monitor.check([.init(id: "p", title: "X", checks: ["app X 1"])])
        XCTAssertEqual(monitor.driftedPages.map(\.id), ["p"])
        let again = DriftMonitor(defaults: defaults, probe: probe)
        XCTAssertEqual(again.driftedPages.map(\.title), ["X"])
        XCTAssertNotNil(again.lastChecked)
        again.prune(keeping: [])
        XCTAssertTrue(again.results.isEmpty)
    }
}

final class InboxReportTests: XCTestCase {
    func testParsesTheServersShapeAndHandTypedLines() {
        let text = """
        # Reports for the operator

        - [ ] 2026-11-06 01:20 UTC · goose · page: Feed · page says "port 4318"; now 4328 · evidence: lsof
        - [x] 2026-11-05 09:00 UTC · cursor · page: Cursor · page says "x"; now y
        - [ ] fix the aka page
        not a report
        """
        let reports = InboxReport.parse(text)
        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(reports[0].agent, "goose")
        XCTAssertEqual(reports[0].evidence, "lsof")
        XCTAssertNotNil(reports[0].reportedDate)
        XCTAssertTrue(reports[1].handled)
        XCTAssertEqual(reports[1].evidence, "")
        XCTAssertTrue(reports[2].malformed)
        XCTAssertEqual(reports[2].what, "fix the aka page")
    }

    func testLineMatchesReportChange() {
        let date = InboxReport.stampFormatter.date(from: "2026-11-06 01:20 UTC")!
        XCTAssertEqual(
            InboxReport.line(agent: "drift", page: "Feed", what: "page says \"a\";\n now b", evidence: "  lsof  ", at: date),
            "- [ ] 2026-11-06 01:20 UTC · drift · page: Feed · page says \"a\"; now b · evidence: lsof")
    }
}

final class DriftIntervalTests: XCTestCase {
    func testDefaultIsOnceADayAndManualNeverRuns() {
        XCTAssertEqual(DriftInterval.default, .oneDay)
        XCTAssertEqual(DriftInterval.fromStored(0), .manual)
        XCTAssertEqual(DriftInterval.fromStored(90000), .oneDay)
        XCTAssertEqual(DriftInterval.allCases.last, .manual)
        let now = Date()
        XCTAssertFalse(DriftInterval.manual.isDue(lastChecked: nil, now: now))
        XCTAssertTrue(DriftInterval.oneDay.isDue(lastChecked: nil, now: now))
        XCTAssertFalse(DriftInterval.oneDay.isDue(lastChecked: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(DriftInterval.oneDay.isDue(lastChecked: now.addingTimeInterval(-86400), now: now))
    }

    func testKeyboardStepsMoveOneStop() {
        XCTAssertEqual(DriftInterval.stepped(from: .oneDay, toward: 3.1), .oneWeek)
        XCTAssertEqual(DriftInterval.stepped(from: .oneDay, toward: 2.9), .twelveHours)
    }
}

/// Parked and archived pages (2.3.0): out of the lists and Drift, still in search.
@MainActor
final class ParkedPagesTests: XCTestCase {
    private func page(_ id: String, _ title: String, status: String, checks: Bool) -> String {
        """
        ---
        title: \(title)
        category: Services
        tags:
          []
        createdAt: 2026-09-13T13:30:00.000Z
        updatedAt: 2026-11-06T00:00:00.000Z
        id: \(id)
        status: \(status)
        \(checks ? "checks:\n  - port 4319" : "")
        ---

        Body of \(title).
        """
    }

    func testParkedPagesLeaveListsAndDriftButStaySearchable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ops-parked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try page("a1", "Feed", status: "active", checks: true).write(to: dir.appendingPathComponent("feed-a1.md"), atomically: true, encoding: .utf8)
        try page("b2", "Reed", status: "parked", checks: true).write(to: dir.appendingPathComponent("reed-b2.md"), atomically: true, encoding: .utf8)
        try page("c3", "Old", status: "Archived", checks: false).write(to: dir.appendingPathComponent("old-c3.md"), atomically: true, encoding: .utf8)
        let store = DocumentStore(folder: dir, watch: false)
        let state = AppState()

        XCTAssertEqual(state.visibleDocuments(in: store).map(\.title), ["Feed"])
        XCTAssertEqual(store.categories.map(\.count), [1])
        // A category whose pages are all parked leaves the sidebar.
        try page("e5", "Golden regression set", status: "parked", checks: false)
            .replacingOccurrences(of: "category: Services", with: "category: Skills")
            .write(to: dir.appendingPathComponent("golden-e5.md"), atomically: true, encoding: .utf8)
        store.load()
        XCTAssertEqual(store.categories.map(\.name), ["Services"])
        XCTAssertTrue(store.parkedDocuments.contains { $0.title == "Golden regression set" })
        state.selection = .parked
        XCTAssertEqual(Set(state.visibleDocuments(in: store).map(\.title)), ["Reed", "Old", "Golden regression set"])
        XCTAssertEqual(DriftMonitor.pages(from: store.documents).map(\.title), ["Feed"])
        XCTAssertEqual(store.search("Reed").first?.title, "Reed")

        // Opening a parked page from search lands on the Parked list.
        state.selection = .all
        state.open(docID: "b2", in: store)
        XCTAssertEqual(state.selection, .parked)
        XCTAssertEqual(state.selectedDocID, "b2")
    }
}

@MainActor
final class CategoryOverviewTests: XCTestCase {
    private func doc(_ title: String, _ category: String) -> OpsDocument {
        OpsDocument(id: title, title: title, category: category, summary: "", tags: [], createdAt: "", updatedAt: "", properties: [], body: "")
    }

    func testPicksTheCategorysOwnOverviewOrIndexPage() {
        let docs = [doc("Hooks overview", "Hooks"), doc("Stop hook", "Hooks"), doc("App Store index", "App Store"),
                    doc("Self-hosted overview", "Self-hosted"), doc("Firecrawl", "Self-hosted"), doc("Feed", "Services")]
        XCTAssertEqual(CategoryOverviewView.overviewPage(in: docs, category: "Hooks")?.title, "Hooks overview")
        XCTAssertEqual(CategoryOverviewView.overviewPage(in: docs, category: "App Store")?.title, "App Store index")
        XCTAssertEqual(CategoryOverviewView.overviewPage(in: docs, category: "Self-hosted")?.title, "Self-hosted overview")
        XCTAssertNil(CategoryOverviewView.overviewPage(in: docs, category: "Services"))
        // A page from another category never counts.
        XCTAssertNil(CategoryOverviewView.overviewPage(in: [doc("Hooks overview", "Hooks")], category: "Agents"))
    }
}
