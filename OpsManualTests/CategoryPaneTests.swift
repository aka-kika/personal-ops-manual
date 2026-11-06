import XCTest
@testable import OpsManual

private func doc(_ title: String, _ category: String, body: String = "", props: [DocProperty] = [], updated: String = "2026-11-01T00:00:00.000Z") -> OpsDocument {
    OpsDocument(id: title, title: title, category: category, summary: "", tags: [], createdAt: updated, updatedAt: updated,
                properties: props + [DocProperty(key: "status", value: "active")], body: body)
}

final class LiveSourcesTests: XCTestCase {
    func testTailscaleNamesPhonesByTheirDNSName() throws {
        let json = """
        {"Self":{"HostName":"KIKA-HUBs-MBP","Online":true},
         "Peer":{"a":{"HostName":"the-zen","Online":true},"b":{"HostName":"alien","Online":false},
                 "c":{"HostName":"localhost","DNSName":"iphone-15-pro-max-1.tail1f9d14.ts.net.","Online":false}}}
        """
        let machines = try XCTUnwrap(LiveProbe.parseTailscale(Data(json.utf8)))
        XCTAssertEqual(machines.map(\.name), ["KIKA-HUBs-MBP", "the-zen", "alien", "iphone-15-pro-max-1"])
        XCTAssertTrue(machines[0].isSelf)
    }

    func testMcpockStatusFile() throws {
        let json = """
        {"counts":{"fine":38,"total":40},"servers":[{"name":"rea","needsAttention":true},{"name":"x","needsAttention":true,"hidden":true},{"name":"ok","needsAttention":false}]}
        """
        let health = try XCTUnwrap(LiveProbe.parseMcpock(Data(json.utf8)))
        XCTAssertEqual(health.fine, 38)
        XCTAssertEqual(health.attention, ["rea"])
    }

    func testLastExitCode() {
        XCTAssertEqual(LiveProbe.parseLastExit("\tstate = not running\n\tlast exit code = 78: EX_CONFIG\n"), 78)
        XCTAssertEqual(LiveProbe.parseLastExit("\tlast exit code = 0\n"), 0)
        XCTAssertNil(LiveProbe.parseLastExit("\tlast exit code = (never exited)\n"))
    }
}

final class CategoryStatusTests: XCTestCase {
    private let now = CategoryStatus.isoDay.date(from: "2026-11-06")!

    private func input(_ docs: [OpsDocument], facts: LiveFacts = LiveFacts(), checks: [DriftResult] = []) -> CategoryStatus.Inputs {
        .init(docs: docs, checkResults: checks, github: GitHubSnapshot(), facts: facts, now: now)
    }

    func testZerosInWordsAndPeachOnlyWhereItNeedsCare() {
        var facts = LiveFacts()
        facts.machines = [.init(name: "mbp", online: true, isSelf: true), .init(name: "alien", online: false, isSelf: false)]
        let s = CategoryStatus.compute(title: "Machines", input([], facts: facts))
        XCTAssertEqual(s.parts.map(\.text), ["1 online", "1 offline"])
        XCTAssertEqual(s.parts.map(\.attention), [false, true])
        XCTAssertEqual(s.rows.map(\.name), ["alien"])
        facts.mcp = .init(fine: 40, total: 40, attention: [])
        XCTAssertEqual(CategoryStatus.compute(title: "MCP", input([], facts: facts)).parts.map(\.text),
                       ["40 of 40 servers healthy", "none need attention"])
        XCTAssertEqual(CategoryStatus.compute(title: "Machines", input([])).unavailable, "Tailscale couldn't be checked.")
    }

    func testVisualsRingSegmentsAndDates() {
        var facts = LiveFacts()
        facts.machines = [.init(name: "alien", online: false, isSelf: false), .init(name: "mbp", online: true, isSelf: true)]
        facts.mcp = .init(fine: 38, total: 40, attention: ["a", "b"])
        XCTAssertEqual(CategoryStatus.compute(title: "Machines", input([], facts: facts)).visual, .segments([true, false]))
        XCTAssertEqual(CategoryStatus.compute(title: "MCP", input([], facts: facts)).visual, .ring(fine: 38, attention: 2))
        // Dates: inside the span only, peach inside the window; none when nothing is dated.
        let docs = [doc("Cursor account", "Accounts", props: [DocProperty(key: "renews", value: "2026-11-14")]),
                    doc("Far account", "Accounts", props: [DocProperty(key: "renews", value: "2027-06-01")]),
                    doc("Soon-ish account", "Accounts", props: [DocProperty(key: "renews", value: "2026-12-26")])]
        guard case .dates(let points, let span, let window, let end)? = CategoryStatus.compute(title: "Accounts", input(docs)).visual else {
            return XCTFail("Accounts should have a date line")
        }
        XCTAssertEqual(points.map(\.name), ["Cursor account", "Soon-ish account"])
        XCTAssertEqual(points.map(\.attention), [true, false])
        XCTAssertEqual(points[0].days, 8, accuracy: 0.01)
        XCTAssertEqual([span, window], [90, 30])
        XCTAssertEqual(end, "in 90 days")
        XCTAssertNil(CategoryStatus.compute(title: "Accounts", input([])).visual)
        XCTAssertNil(CategoryStatus.compute(title: "MCP", input([])).visual)
    }

    func testRenewalsNearestFirstAndMonthlyDays() {
        let docs = [doc("Apple Developer account", "Accounts", props: [DocProperty(key: "renews", value: "2027-02-27")]),
                    doc("xAI account", "Accounts", props: [DocProperty(key: "renews", value: "day 9")]),
                    doc("Ollama cloud account", "Accounts", props: [DocProperty(key: "renews", value: "day 1")]),
                    doc("No date", "Accounts")]
        let s = CategoryStatus.compute(title: "Accounts", input(docs))
        XCTAssertEqual(s.parts.map(\.text), ["2 renewals in the next 30 days"])
        XCTAssertEqual(s.rows.map(\.name), ["xAI account", "Ollama cloud account", "Apple Developer account"])
        XCTAssertEqual(s.rows.map(\.value), ["9 Nov 2026", "1 Dec 2026", "27 Feb 2027"])
        XCTAssertEqual(s.rows.map(\.attention), [true, true, false])
        XCTAssertEqual(CategoryStatus.next("day 31", after: CategoryStatus.isoDay.date(from: "2026-02-10")!),
                       CategoryStatus.isoDay.date(from: "2026-02-28"))
        XCTAssertEqual(CategoryStatus.compute(title: "Domains", input([doc("x.com", "Domains")])).unavailable, "No page has a expires: date yet.")
    }

    func testServicesUpOrDownFromTheirChecks() {
        let a = doc("Feed", "Services"), b = doc("Reed", "Services")
        let ok = DriftResult(pageID: "Feed", pageTitle: "Feed", line: "port 4318", kind: .port, claim: "Port 4318", subject: "4318",
                             pageSays: "listening", now: "node listening", status: .holds, source: "lsof", checkedAt: now)
        var bad = ok; bad.pageID = "Reed"; bad.pageTitle = "Reed"; bad.status = .drifted
        let s = CategoryStatus.compute(title: "Services", input([a, b], checks: [ok, bad]))
        XCTAssertEqual(s.parts.map(\.text), ["1 up", "1 down"])
        XCTAssertEqual(s.rows.map(\.name), ["Reed"])
    }

    func testLastChangedIsTheThreeNewest() {
        let docs = [doc("A", "X", updated: "2026-11-01T00:00:00.000Z"), doc("B", "X", updated: "2026-11-06T00:00:00.000Z"),
                    doc("C", "X", updated: "2026-11-03T00:00:00.000Z"), doc("D", "X", updated: "2026-10-01T00:00:00.000Z")]
        XCTAssertEqual(CategoryStatus.lastChanged(docs), "B, 6 Nov · C, 3 Nov · A, 1 Nov")
    }
}

final class OverviewPageTests: XCTestCase {
    func testOverviewPagesAndTheirIntro() {
        let machines = doc("Machines overview", "Machines", body: "The computers I own.\n\nNot here: the apps on them.\n\n---\n\n## Related\n\n[[x]]")
        XCTAssertTrue(CategoryOverviewPage.isOverview(machines))
        XCTAssertTrue(CategoryOverviewPage.isOverview(doc("MCP overview", "MCP (mine)")))
        XCTAssertFalse(CategoryOverviewPage.isOverview(doc("GitHub index", "GitHub")))
        let intro = CategoryOverviewPage.intro(machines)
        XCTAssertEqual(intro.text, "The computers I own.")
        XCTAssertEqual(intro.notHere, "Not here: the apps on them.")
        let linked = doc("Skills overview", "Skills", body: "Agents reach it through [[skill-librarian]].\n\nNot here: the collection ([[Skill collection|the shelf]]).")
        XCTAssertEqual(CategoryOverviewPage.intro(linked).text, "Agents reach it through skill-librarian.")
        XCTAssertEqual(CategoryOverviewPage.intro(linked).notHere, "Not here: the collection (the shelf).")
    }
}

final class AppStoreStatusTests: XCTestCase {
    private let now = CategoryStatus.isoDay.date(from: "2026-11-06")!

    private func app(_ title: String, summary: String) -> OpsDocument {
        OpsDocument(id: title, title: title, category: "App Store", summary: summary, tags: [], createdAt: "2026-10-16T00:00:00.000Z",
                    updatedAt: "2026-10-16T00:00:00.000Z", properties: [DocProperty(key: "status", value: "active")], body: "")
    }

    func testParsesAscStatus() throws {
        let json = """
        {"app":{"id":"6818254619"},"appstore":{"version":"1.0","state":"WAITING_FOR_REVIEW","createdDate":"2026-10-01T10:13:07-07:00"},
         "review":{"state":"WAITING_FOR_REVIEW","submittedDate":"2026-10-26T15:03:20.15Z"}}
        """
        let state = try XCTUnwrap(AppStoreState.parse(Data(json.utf8)))
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertEqual(state.version, "1.0")
        XCTAssertNotNil(state.submittedAt)
        XCTAssertNil(AppStoreState.parse(Data("{}".utf8)))
    }

    func testAppIDAndPriceFromThePage() {
        let page = app("Static QR (App Store)", summary: "iPhone app, $4.99, 1.0 build 3 waiting for review since 2026-10-26 (app 6818254619)")
        XCTAssertEqual(AppStorePage.appID(page), "6818254619")
        XCTAssertEqual(AppStorePage.price(page), "$4.99")
        XCTAssertEqual(AppStorePage.name(page), "Static QR")
        XCTAssertNil(AppStorePage.appID(app("App Store index", summary: "Every app")))
    }

    func testPeachOnlyForRejectedOrALongWait() {
        let docs = [app("Static QR (App Store)", summary: "$4.99 (app 1000000001)"), app("Background Off (App Store)", summary: "$1.99 (app 1000000002)"),
                    app("Lane (App Store)", summary: "free (app 1000000003)"), app("App Store index", summary: "Every app")]
        var facts = LiveFacts()
        let day: TimeInterval = 86_400
        facts.appStore = ["1000000001": .init(state: "WAITING_FOR_REVIEW", version: "1.0", submittedAt: now.addingTimeInterval(-11 * day)),
                          "1000000002": .init(state: "READY_FOR_DISTRIBUTION", version: "1.0.3", submittedAt: nil)]
        facts.appStoreFailed = ["1000000003"]
        facts.appStoreAt = now
        XCTAssertEqual(docs.compactMap(AppStorePage.appID), ["1000000001", "1000000002", "1000000003"])
        var s = CategoryStatus.compute(title: "App Store", .init(docs: docs, checkResults: [], github: GitHubSnapshot(), facts: facts, now: now))
        XCTAssertEqual(s.rows.map(\.name), ["Background Off", "Lane", "Static QR"])
        XCTAssertEqual(s.rows.map(\.value), ["on sale · 1.0.3 · $1.99", "couldn't check", "waiting for review, 11 days · 1.0 · $4.99"])
        XCTAssertEqual(s.rows.map(\.attention), [false, false, false])
        XCTAssertEqual(s.parts.map(\.text), ["1 on sale", "1 in review", "none rejected"])

        facts.appStore?["1000000001"]?.submittedAt = now.addingTimeInterval(-20 * day)
        facts.appStore?["1000000003"] = .init(state: "REJECTED", version: "1.1", submittedAt: now.addingTimeInterval(-2 * day))
        facts.appStoreFailed = []
        s = CategoryStatus.compute(title: "App Store", .init(docs: docs, checkResults: [], github: GitHubSnapshot(), facts: facts, now: now))
        XCTAssertEqual(s.rows.map(\.attention), [false, true, true])
        XCTAssertEqual(s.rows.map(\.value).dropFirst().first, "rejected, 2 days · 1.1 · free")
        XCTAssertEqual(s.parts.map(\.attention), [false, true, true])
        XCTAssertEqual(s.visual, .ring(fine: 1, attention: 2))
        XCTAssertNil(s.unavailable)
    }

    func testNotReadYetSaysSo() {
        let docs = [app("Static QR (App Store)", summary: "(app 1000000001)")]
        var facts = LiveFacts()
        facts.ascMissing = true
        let s = CategoryStatus.compute(title: "App Store", .init(docs: docs, checkResults: [], github: GitHubSnapshot(), facts: facts, now: now))
        XCTAssertEqual(s.unavailable, "asc is not installed: App Store Connect couldn't be checked.")
    }

    func testIndexPageStandsInForAMissingOverview() {
        var index = app("App Store index", summary: "")
        index.tags = ["app-store", "index"]
        let docs = [app("Static QR (App Store)", summary: ""), index]
        XCTAssertEqual(CategoryOverviewPage.page(for: "App Store", categories: ["App Store"], in: docs)?.title, "App Store index")
        XCTAssertFalse(CategoryOverviewPage.isOverview(index))
    }
}
