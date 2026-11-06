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
    /// Written by the app's check ("## Out of date: ..." sections), not by a reader.
    var outOfDate = false

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
        var inOutOfDate = false
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("## ") { inOutOfDate = line.hasPrefix("## Out of date"); continue }
            guard line.hasPrefix("- [") else { continue }
            let ns = line as NSString
            if let m = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                func group(_ i: Int) -> String {
                    let r = m.range(at: i)
                    return r.location == NSNotFound ? "" : ns.substring(with: r)
                }
                out.append(InboxReport(
                    handled: group(1) == "x", reportedAt: group(2), agent: group(3), page: group(4),
                    what: group(5), evidence: group(6), line: line, lineNumber: index, outOfDate: inOutOfDate))
            } else if line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
                let handled = !line.hasPrefix("- [ ]")
                let rest = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                out.append(InboxReport(
                    handled: handled, reportedAt: "", agent: "", page: "", what: rest, evidence: "",
                    line: line, lineNumber: index, malformed: true, outOfDate: inOutOfDate))
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

    /// Appends one line to the inbox file, creating it with the header when missing,
    /// and starting on a fresh line if the file does not end with one.
    static func append(_ line: String, to inboxURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: inboxURL.path) {
            try header.write(to: inboxURL, atomically: true, encoding: .utf8)
        }
        let existing = try Data(contentsOf: inboxURL)
        var text = line + "\n"
        if let last = existing.last, last != UInt8(ascii: "\n") { text = "\n" + text }
        let handle = try FileHandle(forWritingTo: inboxURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    static func appendFailure(_ error: Error) -> String {
        "The report could not be filed: \(error.localizedDescription) The inbox folder may be locked; ops-lock lock opens it again."
    }

    /// Whether an open line already reports this page and claim.
    static func isOpen(page: String, what: String, in reports: [InboxReport]) -> Bool {
        reports.contains { !$0.handled && $0.page == oneLine(page) && $0.what == oneLine(what) }
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
