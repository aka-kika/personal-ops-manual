import Foundation

/// One claim of one page, after checking it.
struct DriftResult: Identifiable, Hashable, Sendable, Codable {
    enum Status: String, Sendable, Codable { case holds, drifted, unknown }

    var pageID: String
    var pageTitle: String
    var line: String
    var kind: DriftCheck.Kind?
    /// "App version", "Notarized", "Port 4319"…
    var claim: String
    /// The path, server, label or CLI the claim is about.
    var subject: String
    var pageSays: String
    var now: String
    var status: Status
    /// Where the "now" came from, for the report's evidence.
    var source: String
    var checkedAt: Date
    /// When this claim was first seen drifted; kept across checks so the list sorts by it.
    var driftedSince: Date?

    var id: String { "\(pageID)|\(line)|\(claim)" }

    /// The `what` of the report this result files: "page says "App version 2.2.4"; now 2.2.5".
    var reportWhat: String { "page says \"\(claim) \(pageSays)\"; now \(now)" }

    /// One line for the Drift list: "App version: page 2.2.4, now 2.2.5".
    var summary: String { "\(claim): page \(pageSays), now \(now)" }
}

/// Pure: checks + facts in, results out. All the Mac access is in the probe.
enum DriftEvaluator {
    struct Page: Sendable {
        var id: String
        var title: String
        var checks: [String]
    }

    static func evaluate(pages: [Page], probe: some DriftProbing, now: Date = Date()) -> [DriftResult] {
        var mcp: [String: String]?? = .none   // read ~/.claude.json once, only if a page asks
        var out: [DriftResult] = []
        for page in pages {
            for line in page.checks {
                func result(_ claim: String, _ subject: String, _ says: String, _ isNow: String,
                            _ status: DriftResult.Status, _ source: String, kind: DriftCheck.Kind?) -> DriftResult {
                    DriftResult(pageID: page.id, pageTitle: page.title, line: line, kind: kind, claim: claim,
                                subject: subject, pageSays: says, now: isNow, status: status, source: source, checkedAt: now)
                }
                let check: DriftCheck
                switch DriftCheck.parse(line) {
                case .success(let c): check = c
                case .failure(let error):
                    out.append(result("Check line", line, line, error.message, .unknown, "the page's checks list", kind: nil))
                    continue
                }
                switch check.kind {
                case .repo:
                    continue   // never parsed from a checks: line
                case .app:
                    let facts = probe.app(check.subject)
                    switch facts {
                    case .missing(let path):
                        out.append(result("App version", path, check.expected ?? "installed", "not installed", .drifted, path, kind: .app))
                    case .installed(let path, let version):
                        let source = "\(path) Info.plist"
                        if let expected = check.expected {
                            if let version {
                                out.append(result("App version", path, expected, version,
                                                  sameVersion(expected, version) ? .holds : .drifted, source, kind: .app))
                            } else {
                                out.append(result("App version", path, expected, "no version in Info.plist", .unknown, source, kind: .app))
                            }
                        } else {
                            out.append(result("App version", path, "installed", version.map { "installed \($0)" } ?? "installed",
                                              .holds, path, kind: .app))
                        }
                        if check.wantsNotarized {
                            let source = "spctl --assess \(path)"
                            switch probe.notarization(path: path) {
                            case .notarized: out.append(result("Notarized", path, "yes", "yes", .holds, source, kind: .app))
                            case .signedNotNotarized(let s): out.append(result("Notarized", path, "yes", "signed, not notarized (\(s))", .drifted, source, kind: .app))
                            case .rejected(let s): out.append(result("Notarized", path, "yes", "no (\(s))", .drifted, source, kind: .app))
                            case .unknown(let why): out.append(result("Notarized", path, "yes", why, .unknown, source, kind: .app))
                            }
                        }
                    }
                case .mcp:
                    if case .none = mcp { mcp = .some(probe.mcpServers()) }
                    let servers = mcp ?? nil
                    let source = "~/.claude.json"
                    if let servers {
                        if let scope = servers[check.subject] {
                            out.append(result("MCP server", check.subject, "wired", "wired (\(scope))", .holds, source, kind: .mcp))
                        } else {
                            out.append(result("MCP server", check.subject, "wired", "missing", .drifted, source, kind: .mcp))
                        }
                    } else {
                        out.append(result("MCP server", check.subject, "wired", "~/.claude.json could not be read", .unknown, source, kind: .mcp))
                    }
                case .port:
                    let port = Int(check.subject) ?? 0
                    let says = check.expected.map { "\($0) listening" } ?? "listening"
                    let source = "lsof -iTCP:\(port) -sTCP:LISTEN"
                    switch probe.listeners(port: port) {
                    case .nothing:
                        out.append(result("Port \(port)", check.subject, says, "nothing listening", .drifted, source, kind: .port))
                    case .listening(let names):
                        let shown = names.joined(separator: ", ")
                        let holds = check.expected.map { want in names.contains { processMatches($0, want) } } ?? true
                        out.append(result("Port \(port)", check.subject, says, "\(shown) listening", holds ? .holds : .drifted, source, kind: .port))
                    case .unknown(let why):
                        out.append(result("Port \(port)", check.subject, says, why, .unknown, source, kind: .port))
                    }
                case .launchd:
                    let says = check.wantsRunning ? "running" : "loaded"
                    let source = "launchctl print gui/\(getuid())/\(check.subject)"
                    switch probe.launchd(label: check.subject) {
                    case .notLoaded:
                        out.append(result("Launch job", check.subject, says, "not loaded", .drifted, source, kind: .launchd))
                    case .loaded(let running):
                        let isNow = running ? "running" : "loaded, not running"
                        let holds = !check.wantsRunning || running
                        out.append(result("Launch job", check.subject, says, isNow, holds ? .holds : .drifted, source, kind: .launchd))
                    case .unknown(let why):
                        out.append(result("Launch job", check.subject, says, why, .unknown, source, kind: .launchd))
                    }
                case .cli:
                    let says = check.expected ?? "installed"
                    switch probe.cli(check.subject) {
                    case .notFound:
                        out.append(result("CLI version", check.subject, says, "not on PATH", .unknown, "PATH folders", kind: .cli))
                    case .found(let path, let version):
                        let source = "\(path) --version"
                        if let expected = check.expected {
                            if let version {
                                out.append(result("CLI version", path, expected, version,
                                                  sameVersion(expected, version) ? .holds : .drifted, source, kind: .cli))
                            } else {
                                out.append(result("CLI version", path, expected, "no version in its output", .unknown, source, kind: .cli))
                            }
                        } else {
                            out.append(result("CLI version", path, "installed", version.map { "installed \($0)" } ?? "installed", .holds, source, kind: .cli))
                        }
                    case .unknown(let why):
                        out.append(result("CLI version", check.subject, says, why, .unknown, "PATH folders", kind: .cli))
                    }
                }
            }
        }
        return out
    }

    /// "v2.2.5" and "2.2.5" are the same version.
    static func sameVersion(_ a: String, _ b: String) -> Bool {
        func clean(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespaces).lowercased()
            return t.hasPrefix("v") ? String(t.dropFirst()) : t
        }
        return clean(a) == clean(b)
    }

    /// lsof shortens some names ("codync-ho"), so either one starting with the other counts.
    static func processMatches(_ actual: String, _ expected: String) -> Bool {
        let a = actual.lowercased(), e = expected.lowercased()
        return !a.isEmpty && !e.isEmpty && (a.hasPrefix(e) || e.hasPrefix(a))
    }

    /// Keeps `driftedSince` from the last check for claims that are still drifted.
    static func carryOver(_ fresh: [DriftResult], from previous: [DriftResult]) -> [DriftResult] {
        let since = Dictionary(previous.compactMap { r in r.driftedSince.map { (r.id, $0) } }, uniquingKeysWith: { a, _ in a })
        return fresh.map { r in
            var r = r
            if r.status == .drifted { r.driftedSince = since[r.id] ?? r.checkedAt }
            return r
        }
    }
}
