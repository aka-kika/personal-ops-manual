import Foundation

/// What App Store Connect says about one app, from `asc status` (Kika, 2026-11-06:
/// "maybe status - in review and so on"). Read only: the app never submits or changes
/// anything in App Store Connect.
struct AppStoreState: Sendable, Codable, Hashable {
    /// The latest App Store version's state, as App Store Connect names it (`WAITING_FOR_REVIEW`).
    var state: String
    var version: String?
    /// When the latest submission went to review: the start of "waiting" and "in review".
    var submittedAt: Date?

    enum Phase: Equatable {
        case onSale, waiting, inReview, pendingRelease, rejected, preparing, removed, other(String)
    }

    var phase: Phase {
        switch state.uppercased() {
        case "READY_FOR_DISTRIBUTION", "READY_FOR_SALE": .onSale
        case "WAITING_FOR_REVIEW": .waiting
        case "IN_REVIEW": .inReview
        case "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "ACCEPTED", "PROCESSING_FOR_DISTRIBUTION", "PENDING_CONTRACT": .pendingRelease
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": .rejected
        case "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED": .preparing
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE", "NOT_APPLICABLE": .removed
        default: .other(state.lowercased().replacingOccurrences(of: "_", with: " "))
        }
    }

    /// `asc status --app <id> --include app,appstore,review` (JSON).
    static func parse(_ data: Data) -> AppStoreState? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let store = root["appstore"] as? [String: Any],
              let state = store["state"] as? String else { return nil }
        let review = root["review"] as? [String: Any]
        let submitted = (review?["submittedDate"] as? String).flatMap(Self.date)
        return AppStoreState(state: state, version: store["version"] as? String, submittedAt: submitted)
    }

    /// App Store Connect writes both "2026-10-26T15:03:20.15Z" and "2026-10-01T10:13:07-07:00".
    static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// The facts an App Store page carries itself: its App Store Connect id and its price.
enum AppStorePage {
    static let category = "App Store"

    /// `app_id:` in the frontmatter, else "(app 6818254619)" in the summary, else the
    /// "| App ID | 6818254619 |" row of the page's table.
    static func appID(_ doc: OpsDocument) -> String? {
        for key in ["app_id", "appstore_id", "asc_id"] {
            if let v = GitHubMatcher.property(doc, key), v.allSatisfy(\.isNumber) { return v }
        }
        if let id = firstMatch(#"\(app (\d{6,12})\)"#, in: doc.summary) { return id }
        return firstMatch(#"\|\s*App ID\s*\|\s*(\d{6,12})\s*\|"#, in: doc.body)
    }

    /// `price:` in the frontmatter, else the first "$4.99" (or "Free") in the summary.
    static func price(_ doc: OpsDocument) -> String? {
        if let p = GitHubMatcher.property(doc, "price") { return p }
        if let p = firstMatch(#"(\$\d+(?:\.\d{2})?)"#, in: doc.summary) { return p }
        return doc.summary.range(of: "free", options: .caseInsensitive) != nil ? "free" : nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// The name without " (App Store)", which every page in the category carries.
    static func name(_ doc: OpsDocument) -> String {
        doc.title.replacingOccurrences(of: " (App Store)", with: "")
    }
}

/// Reads App Store Connect through the `asc` login already on this Mac. Fixed program,
/// fixed arguments, no shell, read-only command.
struct AppStoreProbe: Sendable {
    var home: String = NSHomeDirectory()

    var tool: String? {
        DriftProbe(home: home).cliFolders.map { "\($0)/asc" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func status(appID: String) -> AppStoreState? {
        guard let asc = tool, appID.allSatisfy(\.isNumber),
              let out = ProcessRunner.run(asc, ["status", "--app", appID, "--include", "app,appstore,review"], timeout: 30),
              out.status == 0 else { return nil }
        return AppStoreState.parse(Data(out.stdout.utf8))
    }
}
