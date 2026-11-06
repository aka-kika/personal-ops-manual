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
        let docs = [doc("A", "X", updated: "2026-11-01T00:00:00.000Z"), doc("B (release)", "X", updated: "2026-11-06T00:00:00.000Z"),
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
    }
}
