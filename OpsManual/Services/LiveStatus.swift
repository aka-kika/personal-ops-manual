import Foundation
import Observation

/// The few live facts the category pane needs beyond Drift and GitHub: who is online
/// on Tailscale, what mcpock says about the MCP servers, and the last exit code of
/// launch jobs. All read only; each source can be missing ("couldn't check").
struct LiveFacts: Sendable, Codable {
    struct Machine: Sendable, Codable, Hashable {
        var name: String
        var online: Bool
        var isSelf: Bool
    }
    struct MCPHealth: Sendable, Codable, Hashable {
        var fine: Int
        var total: Int
        /// Servers mcpock marks as needing attention.
        var attention: [String]
    }

    var machines: [Machine]?
    var mcp: MCPHealth?
    /// Last exit code by launchd label (only labels that are loaded).
    var exitCodes: [String: Int] = [:]
    var fetchedAt: Date?

    /// App Store Connect state by app id (nil until the first read).
    var appStore: [String: AppStoreState]?
    /// App ids whose last `asc status` gave no answer.
    var appStoreFailed: Set<String> = []
    var appStoreAt: Date?
    var ascMissing = false
}

protocol LiveProbing: Sendable {
    func machines() -> [LiveFacts.Machine]?
    func mcpHealth() -> LiveFacts.MCPHealth?
    func lastExit(label: String) -> Int?
}

struct LiveProbe: LiveProbing {
    var home: String = NSHomeDirectory()

    func machines() -> [LiveFacts.Machine]? {
        let tools = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        guard let tool = tools.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let out = ProcessRunner.run(tool, ["status", "--json"], timeout: 8), out.status == 0 else { return nil }
        return Self.parseTailscale(Data(out.stdout.utf8))
    }

    /// `tailscale status --json`: Self plus Peer. Phones report "localhost" as their
    /// host name, so the first label of the DNS name is used for them.
    static func parseTailscale(_ data: Data) -> [LiveFacts.Machine]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func machine(_ node: [String: Any], isSelf: Bool) -> LiveFacts.Machine? {
            var name = node["HostName"] as? String ?? ""
            if name.isEmpty || name == "localhost", let dns = node["DNSName"] as? String {
                name = String(dns.split(separator: ".").first ?? "")
            }
            guard !name.isEmpty else { return nil }
            return .init(name: name, online: node["Online"] as? Bool ?? false, isSelf: isSelf)
        }
        var out: [LiveFacts.Machine] = []
        if let me = root["Self"] as? [String: Any], let m = machine(me, isSelf: true) { out.append(m) }
        for peer in ((root["Peer"] as? [String: Any]) ?? [:]).values.compactMap({ $0 as? [String: Any] }) {
            if let m = machine(peer, isSelf: false) { out.append(m) }
        }
        return out.sorted { ($0.isSelf ? 0 : 1, $0.online ? 0 : 1, $0.name.lowercased()) < ($1.isSelf ? 0 : 1, $1.online ? 0 : 1, $1.name.lowercased()) }
    }

    func mcpHealth() -> LiveFacts.MCPHealth? {
        let url = URL(fileURLWithPath: home + "/Library/Application Support/mcpock/status.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Self.parseMcpock(data)
    }

    /// mcpock's status.json: counts.fine, counts.total, servers[].needsAttention.
    static func parseMcpock(_ data: Data) -> LiveFacts.MCPHealth? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counts = root["counts"] as? [String: Any] else { return nil }
        let servers = root["servers"] as? [[String: Any]] ?? []
        let attention = servers.filter { ($0["needsAttention"] as? Bool) == true && ($0["hidden"] as? Bool) != true }
            .compactMap { $0["name"] as? String }.sorted()
        return .init(fine: counts["fine"] as? Int ?? 0, total: counts["total"] as? Int ?? servers.count, attention: attention)
    }

    func lastExit(label: String) -> Int? {
        guard let out = ProcessRunner.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"], timeout: 5), out.status == 0 else { return nil }
        return Self.parseLastExit(out.stdout)
    }

    /// "last exit code = 0" (or "(never exited)").
    static func parseLastExit(_ text: String) -> Int? {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("last exit code = ") else { continue }
            return Int(t.dropFirst("last exit code = ".count).prefix { $0 == "-" || $0.isNumber })
        }
        return nil
    }
}

@MainActor
@Observable
final class LiveStatusMonitor {
    private(set) var facts = LiveFacts()
    private(set) var isFetching = false
    private(set) var isFetchingAppStore = false
    @ObservationIgnored private let probe: any LiveProbing
    @ObservationIgnored private let appStoreProbe: AppStoreProbe
    @ObservationIgnored private let defaults: UserDefaults

    init(probe: any LiveProbing = LiveProbe(), appStoreProbe: AppStoreProbe = AppStoreProbe(), defaults: UserDefaults = .standard) {
        self.probe = probe
        self.appStoreProbe = appStoreProbe
        self.defaults = defaults
        // The last App Store answer shows at once; the pane reads again when it opens.
        if let data = defaults.data(forKey: Self.appStoreKey),
           let saved = try? JSONDecoder().decode(SavedAppStore.self, from: data) {
            facts.appStore = saved.states
            facts.appStoreAt = saved.at
        }
    }

    static let appStoreKey = "appStoreStatus"
    private struct SavedAppStore: Codable { var states: [String: AppStoreState]; var at: Date }

    /// Reads `asc status` for each app id, all at once (about 3 s each). `force` (Cmd-R)
    /// reads again even when the last read is under a minute old.
    func refreshAppStore(ids: [String], force: Bool = false) async {
        guard !ids.isEmpty, !isFetchingAppStore else { return }
        if !force, let at = facts.appStoreAt, Date().timeIntervalSince(at) < 60,
           ids.allSatisfy({ facts.appStore?[$0] != nil || facts.appStoreFailed.contains($0) }) { return }
        isFetchingAppStore = true
        let probe = appStoreProbe
        let result: (states: [String: AppStoreState], failed: Set<String>, missing: Bool) = await Task.detached(priority: .utility) {
            guard probe.tool != nil else { return ([:], Set(ids), true) }
            let box = AppStoreBox()
            DispatchQueue.concurrentPerform(iterations: ids.count) { i in
                box.put(ids[i], probe.status(appID: ids[i]))
            }
            return (box.states, box.failed, false)
        }.value
        var merged = facts.appStore ?? [:]
        for (id, state) in result.states { merged[id] = state }
        facts.appStore = merged
        facts.appStoreFailed = result.failed
        facts.ascMissing = result.missing
        facts.appStoreAt = Date()
        if !result.states.isEmpty, let data = try? JSONEncoder().encode(SavedAppStore(states: merged, at: Date())) {
            defaults.set(data, forKey: Self.appStoreKey)
        }
        isFetchingAppStore = false
    }

    /// Fetches again when the last fetch is older than a minute (the pane calls this on appear).
    func refreshIfStale(labels: [String]) async {
        if let at = facts.fetchedAt, Date().timeIntervalSince(at) < 60, labels.allSatisfy({ facts.exitCodes[$0] != nil }) { return }
        guard !isFetching else { return }
        isFetching = true
        let probe = self.probe
        let previous = facts
        let fresh = await Task.detached(priority: .utility) {
            var f = previous
            f.exitCodes = [:]
            f.machines = probe.machines()
            f.mcp = probe.mcpHealth()
            for label in labels { if let code = probe.lastExit(label: label) { f.exitCodes[label] = code } }
            f.fetchedAt = Date()
            return f
        }.value
        // Keep what the App Store read found meanwhile.
        var kept = fresh
        kept.appStore = facts.appStore
        kept.appStoreFailed = facts.appStoreFailed
        kept.appStoreAt = facts.appStoreAt
        kept.ascMissing = facts.ascMissing
        facts = kept
        isFetching = false
    }
}

/// Collects the parallel `asc status` answers.
private final class AppStoreBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var states: [String: AppStoreState] = [:]
    private(set) var failed: Set<String> = []

    func put(_ id: String, _ state: AppStoreState?) {
        lock.lock(); defer { lock.unlock() }
        if let state { states[id] = state } else { failed.insert(id) }
    }
}
