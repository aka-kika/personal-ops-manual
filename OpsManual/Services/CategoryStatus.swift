import Foundation

/// The category pane (Kika, 2026-11-06, mockup category-pane-v4): what lives here,
/// one quiet status line, last changed. Status is plain text: numbers in normal
/// weight, peach only where something needs care, zeros said in words.
struct CategoryStatus: Equatable {
    struct Part: Equatable {
        var text: String
        var attention = false
    }
    struct Row: Equatable {
        var name: String
        var value: String
        var attention = false
    }

    var label = "STATUS"
    var parts: [Part] = []
    var rows: [Row] = []
    /// Shown grey instead of a status when the source could not be read.
    var unavailable: String?

    var isEmpty: Bool { parts.isEmpty && rows.isEmpty && unavailable == nil }

    /// "3 repos with work not saved" or "no repos with work not saved".
    static func count(_ n: Int, _ one: String, _ many: String, attention: Bool = false) -> Part {
        if n == 0 { return Part(text: "no \(many)") }
        return Part(text: "\(n) \(n == 1 ? one : many)", attention: attention)
    }

    struct Inputs {
        var docs: [OpsDocument]
        var checkResults: [DriftResult]
        var github: GitHubSnapshot
        var facts: LiveFacts
        var now: Date = Date()
    }

    static func compute(title: String, _ input: Inputs) -> CategoryStatus {
        switch title {
        case GitHubMatcher.category: return github(input)
        case "Machines": return machines(input)
        case "MCP": return mcp(input)
        case "Accounts": return dated(input, key: "renews", window: 30, noun: ("renewal", "renewals"), soon: "in the next 30 days")
        case "Domains": return dated(input, key: "expires", window: 60, noun: ("expiry", "expiries"), soon: "in the next 60 days")
        case "Automations": return automations(input)
        case "Services", "Self-hosted": return upDown(input)
        default: return generic(input)
        }
    }

    static func github(_ input: Inputs) -> CategoryStatus {
        var s = CategoryStatus()
        let infos = input.docs.map { ($0, GitHubMonitor.info(for: $0, in: input.github)) }
        let unsaved = infos.filter { $0.1.local?.hasUnsavedWork ?? false }
        let prs = infos.compactMap { $0.1.remote?.openPRs }.reduce(0, +)
        let failing = infos.filter { $0.1.remote?.ci == .failure }
        s.parts = [count(unsaved.count, "repo with work not saved", "repos with work not saved", attention: true),
                   count(prs, "open pull request", "open pull requests", attention: true),
                   count(failing.count, "failing build", "failing builds", attention: true)]
        for (doc, info) in unsaved {
            guard let local = info.local else { continue }
            var bits: [String] = []
            if local.uncommitted > 0 { bits.append("\(local.uncommitted) uncommitted") }
            if local.ahead > 0 { bits.append("\(local.ahead) unpushed") }
            s.rows.append(Row(name: doc.title, value: bits.joined(separator: " · "), attention: true))
        }
        for (doc, _) in failing { s.rows.append(Row(name: doc.title, value: "build failed", attention: true)) }
        if input.github.refreshedAt == nil { s.unavailable = "Not refreshed yet: right-click GitHub in the sidebar." }
        return s
    }

    static func machines(_ input: Inputs) -> CategoryStatus {
        var s = CategoryStatus()
        guard let machines = input.facts.machines else {
            s.unavailable = "Tailscale couldn't be checked."
            return s
        }
        let online = machines.filter(\.online).count
        let offline = machines.filter { !$0.online }
        s.parts = [Part(text: "\(online) online"), count(offline.count, "offline", "offline", attention: true)]
        if offline.isEmpty { s.parts[1] = Part(text: "none offline") }
        s.rows = offline.map { Row(name: $0.name, value: "offline") }
        return s
    }

    static func mcp(_ input: Inputs) -> CategoryStatus {
        var s = CategoryStatus()
        guard let health = input.facts.mcp else {
            s.unavailable = "mcpock couldn't be read (is it running?)."
            return s
        }
        s.parts = [Part(text: "\(health.fine) of \(health.total) servers healthy"),
                   count(health.attention.count, "needs attention", "need attention", attention: true)]
        if health.attention.isEmpty { s.parts[1] = Part(text: "none need attention") }
        s.rows = health.attention.map { Row(name: $0, value: "needs attention", attention: true) }
        return s
    }

    /// Accounts (`renews:`) and Domains (`expires:`): dates written on the pages, nearest first.
    static func dated(_ input: Inputs, key: String, window: Int, noun: (String, String), soon: String) -> CategoryStatus {
        var s = CategoryStatus()
        let dated: [(OpsDocument, Date)] = input.docs.compactMap { doc in
            GitHubMatcher.property(doc, key).flatMap { Self.next($0, after: input.now) }.map { (doc, $0) }
        }.sorted { $0.1 < $1.1 }
        guard !dated.isEmpty else {
            s.unavailable = "No page has a \(key): date yet."
            return s
        }
        let limit = input.now.addingTimeInterval(TimeInterval(window) * 86_400)
        let close = dated.filter { $0.1 <= limit }
        s.parts = [Part(text: close.isEmpty ? "no \(noun.1) \(soon)" : "\(close.count) \(close.count == 1 ? noun.0 : noun.1) \(soon)",
                        attention: !close.isEmpty)]
        s.rows = dated.prefix(3).map { doc, date in
            let passed = date < Calendar.current.startOfDay(for: input.now)
            return Row(name: doc.title, value: (passed ? "passed " : "") + Self.dayFormatter.string(from: date), attention: date <= limit)
        }
        return s
    }

    static func automations(_ input: Inputs) -> CategoryStatus {
        var s = CategoryStatus()
        let ids = Set(input.docs.map(\.id))
        let jobs = input.checkResults.filter { ids.contains($0.pageID) && $0.kind == .launchd }
        guard !jobs.isEmpty else { return generic(input) }
        let notLoaded = jobs.filter { $0.now == "not loaded" }
        let failed = jobs.filter { r in r.now != "not loaded" && (input.facts.exitCodes[r.subject] ?? 0) != 0 }
        s.parts = [Part(text: "\(jobs.count - notLoaded.count) loaded"),
                   count(notLoaded.count, "not loaded", "not loaded", attention: true),
                   count(failed.count, "last run failed", "last runs failed", attention: true)]
        if notLoaded.isEmpty { s.parts[1] = Part(text: "none missing") }
        s.rows = notLoaded.map { Row(name: $0.subject, value: "not loaded", attention: true) }
            + failed.map { Row(name: $0.subject, value: "exit \(input.facts.exitCodes[$0.subject] ?? 0)", attention: true) }
        return s
    }

    /// A page is up when all its checks hold, down when one is out of date.
    static func upDown(_ input: Inputs) -> CategoryStatus {
        var s = CategoryStatus()
        let byPage = Dictionary(grouping: input.checkResults.filter { r in input.docs.contains { $0.id == r.pageID } }, by: \.pageID)
        guard !byPage.isEmpty else { return s }
        let down = input.docs.filter { byPage[$0.id]?.contains { $0.status == .drifted } ?? false }
        let up = input.docs.filter { doc in byPage[doc.id].map { $0.allSatisfy { $0.status != .drifted } } ?? false }
        s.parts = [Part(text: "\(up.count) up"), count(down.count, "down", "down", attention: true)]
        if down.isEmpty { s.parts[1] = Part(text: "none down") }
        s.rows = down.map { Row(name: $0.title, value: "down", attention: true) }
        return s
    }

    /// Any other category: what its checks: lines say, when it has some.
    static func generic(_ input: Inputs) -> CategoryStatus {
        var s = CategoryStatus()
        let ids = Set(input.docs.map(\.id))
        let results = input.checkResults.filter { ids.contains($0.pageID) && $0.status != .unknown }
        guard !results.isEmpty else { return s }
        let drifted = results.filter { $0.status == .drifted }
        s.parts = [Part(text: "\(results.count - drifted.count) of \(results.count) checks hold"),
                   count(drifted.count, "out of date", "out of date", attention: true)]
        if drifted.isEmpty { s.parts[1] = Part(text: "none out of date") }
        s.rows = drifted.map { Row(name: $0.pageTitle, value: "\($0.claim): \($0.now)", attention: true) }
        return s
    }

    /// "Recall daemon, 6 Nov · Feed, 6 Nov · aka LAN sidecar, 5 Nov".
    static func lastChanged(_ docs: [OpsDocument]) -> String {
        docs.sorted { $0.updatedDate > $1.updatedDate }.prefix(3)
            .map { "\($0.title), \(Self.shortDay.string(from: $0.updatedDate))" }
            .joined(separator: " · ")
    }

    static func day(_ text: String) -> Date? { isoDay.date(from: String(text.prefix(10))) }

    /// A `renews:` / `expires:` value: "2027-02-27", or "day 12" for every month on the 12th
    /// (the next 12th from today, so a monthly renewal never goes stale).
    static func next(_ value: String, after now: Date) -> Date? {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        if v.hasPrefix("day "), let dayOfMonth = Int(v.dropFirst(4)), (1...31).contains(dayOfMonth) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let today = cal.startOfDay(for: now)
            var parts = cal.dateComponents([.year, .month], from: today)
            for _ in 0..<3 {
                let range = cal.range(of: .day, in: .month, for: cal.date(from: parts)!)!
                parts.day = min(dayOfMonth, range.count)
                if let date = cal.date(from: parts), date >= today { return date }
                parts.day = nil
                parts.month = (parts.month ?? 1) + 1
            }
            return nil
        }
        return day(v)
    }

    nonisolated(unsafe) static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    nonisolated(unsafe) static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f
    }()
}

/// The page that says what lives in a category: "<Category> overview" ("MCP overview"
/// for the two MCP categories). It is not counted or listed with the category's pages;
/// the list column shows it as a footer line.
enum CategoryOverviewPage {
    static func isOverview(_ doc: OpsDocument) -> Bool {
        let t = doc.title.trimmingCharacters(in: .whitespaces).lowercased()
        if t == doc.category.lowercased() + " overview" { return true }
        return MCPGroups.categories.contains(doc.category) && t == "mcp overview"
    }

    static func page(for title: String, in docs: [OpsDocument]) -> OpsDocument? {
        docs.first { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == title.lowercased() + " overview" }
    }

    /// The first paragraph, plus a "Not here:" line when the page has one.
    static func intro(_ doc: OpsDocument) -> (text: String, notHere: String?) {
        let body = MarkdownText.stripLeadingTitle(doc.body, title: doc.title)
        var paragraphs: [String] = []
        var current: [String] = []
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("---") || t.hasPrefix(">") {
                if !current.isEmpty { paragraphs.append(current.joined(separator: " ")); current = [] }
                continue
            }
            current.append(t)
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        let notHere = paragraphs.first { $0.lowercased().hasPrefix("not here") }
        let first = paragraphs.first { !$0.lowercased().hasPrefix("not here") } ?? ""
        return (MarkdownText.strip(first), notHere.map(MarkdownText.strip))
    }
}
