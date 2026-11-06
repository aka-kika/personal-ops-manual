import Foundation

/// One line of `_inbox/reports.md`: a reader's report, filed with `report_change`
/// (or Drift's Report button) for the operator. The app only reads these and adds
/// new ones; the operator ticks and clears them.
struct InboxReport: Identifiable, Hashable, Sendable {
    var handled: Bool
    /// "2026-11-06 01:20 UTC", as written.
    var reportedAt: String
    var agent: String
    var page: String
    var what: String
    var evidence: String
    /// The line exactly as it is in the file.
    var line: String
    /// Its place in the file, so two identical lines stay two rows.
    var lineNumber: Int
    /// A `- [ ]` line that does not have the report_change shape (typed by hand).
    var malformed = false

    var id: Int { lineNumber }

    var reportedDate: Date? { Self.stampFormatter.date(from: reportedAt) }

    nonisolated(unsafe) static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return f
    }()

    /// Same pattern as `parseReports()` in mcp/server.mjs.
    nonisolated(unsafe) private static let pattern = try! NSRegularExpression(
        pattern: #"^- \[( |x)\] (\S+ \S+ UTC) · (.+?) · page: (.+?) · (.+?)(?: · evidence: (.*))?$"#)

    /// Every checkbox line in the file, in file order. Lines that do not parse come back
    /// with `malformed` set and the whole line in `what`.
    static func parse(_ text: String) -> [InboxReport] {
        var out: [InboxReport] = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard line.hasPrefix("- [") else { continue }
            let ns = line as NSString
            if let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                func group(_ i: Int) -> String {
                    let r = m.range(at: i)
                    return r.location == NSNotFound ? "" : ns.substring(with: r)
                }
                out.append(InboxReport(
                    handled: group(1) == "x", reportedAt: group(2), agent: group(3), page: group(4),
                    what: group(5), evidence: group(6), line: line, lineNumber: index))
            } else if line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
                let handled = !line.hasPrefix("- [ ]")
                let rest = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                out.append(InboxReport(
                    handled: handled, reportedAt: "", agent: "", page: "", what: rest, evidence: "",
                    line: line, lineNumber: index, malformed: true))
            }
        }
        return out
    }

    /// The line `report_change` would write for these values.
    static func line(agent: String, page: String, what: String, evidence: String?, at date: Date = Date()) -> String {
        var line = "- [ ] \(stampFormatter.string(from: date)) · \(oneLine(agent)) · page: \(oneLine(page)) · \(oneLine(what))"
        if let evidence, !oneLine(evidence).isEmpty { line += " · evidence: \(oneLine(evidence))" }
        return line
    }

    static func oneLine(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// What a new inbox file starts with; the same words as `INBOX_HEADER` in mcp/server.mjs.
    static let header = """
    # Reports for the operator

    One line per report, appended by agents through the personal-ops-manual MCP
    (report_change). Open reports start with `- [ ]`; the operator applies what is
    true to the pages, then ticks the box (`- [x]`). Nothing here is a page; the
    manual's pages are edited only by the operator.


    """
}
