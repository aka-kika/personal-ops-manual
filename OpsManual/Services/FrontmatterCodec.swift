import Foundation

/// Reads and writes the exact frontmatter shape used by the Node app
/// (document-store.ts). Key order and quoting are fixed so both apps and
/// hand edits produce identical bytes.
///
/// Two rough edges are deliberate, because the Node app has them and the files
/// must stay byte-identical between the two:
/// - A quoted value containing a newline is not escaped. The newline is written
///   literally, which yields YAML that a strict parser would reject.
/// - A custom property with an empty key or an empty value is dropped rather
///   than written as an empty scalar.
/// Fixing either one here would make this app write different bytes than the
/// Node app for the same document, so both stay as they are.
enum FrontmatterCodec {
    struct Parsed {
        var fields: [(key: String, value: String)] = []
        var tags: [String] = []
        var body: String = ""
        func value(_ key: String) -> String? { fields.first { $0.key == key }?.value }
    }

    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func nowISO() -> String { isoFormatter.string(from: Date()) }

    static func parse(_ raw: String) -> Parsed {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n") else { return Parsed(body: text) }
        let afterOpen = text.index(text.startIndex, offsetBy: 4)
        guard let closeRange = text.range(of: "\n---", range: afterOpen..<text.endIndex) else {
            return Parsed(body: text)
        }
        // The closing fence must be followed by newline or end of text.
        var bodyStart = closeRange.upperBound
        if bodyStart < text.endIndex {
            guard text[bodyStart] == "\n" else { return Parsed(body: text) }
            bodyStart = text.index(after: bodyStart)
        }
        let block = String(text[afterOpen..<closeRange.lowerBound])
        var parsed = Parsed()
        var collectingTags = false
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if collectingTags, let item = listItem(line) {
                parsed.tags.append(unquote(item))
                continue
            }
            collectingTags = false
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "tags" {
                if value.isEmpty || value == "[]" { collectingTags = true; continue }
                let inner = value.dropFirst(value.hasPrefix("[") ? 1 : 0).dropLast(value.hasSuffix("]") ? 1 : 0)
                parsed.tags = inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                continue
            }
            parsed.fields.append((key: key, value: unquote(value)))
        }
        parsed.body = String(text[bodyStart...]).drop { $0.isWhitespace }.description
        return parsed
    }

    static func document(from raw: String) -> OpsDocument? {
        let p = parse(raw)
        guard let id = p.value("id"), !id.isEmpty else { return nil }
        let props = p.fields.filter { !OpsDocument.knownKeys.contains($0.key) }
            .map { DocProperty(key: $0.key, value: $0.value) }
        return OpsDocument(
            id: id,
            title: p.value("title").flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
            category: p.value("category").flatMap { $0.isEmpty ? nil : $0 } ?? "Uncategorized",
            summary: p.value("summary") ?? "",
            tags: p.tags,
            createdAt: p.value("createdAt") ?? nowISO(),
            updatedAt: p.value("updatedAt") ?? nowISO(),
            properties: props,
            body: p.body)
    }

    static func serialize(_ doc: OpsDocument) -> String {
        let tagLines = doc.tags.isEmpty ? "  []" : doc.tags.map { "  - \(escape($0))" }.joined(separator: "\n")
        let summaryLine = doc.summary.isEmpty ? "" : "summary: \(escape(doc.summary))\n"
        let custom = doc.properties
            .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.key): \(escape($0.value))" }
            .joined(separator: "\n")
        let customBlock = custom.isEmpty ? "" : custom + "\n"
        return """
        ---
        title: \(escape(doc.title))
        category: \(escape(doc.category))
        \(summaryLine)tags:
        \(tagLines)
        createdAt: \(doc.createdAt)
        updatedAt: \(doc.updatedAt)
        id: \(doc.id)
        \(customBlock)---

        \(doc.body)
        """
    }

    /// Quote only when the value contains one of : # newline [ ] { } , " '
    static func escape(_ value: String) -> String {
        let special: Set<Character> = [":", "#", "\n", "[", "]", "{", "}", ",", "\"", "'"]
        guard value.contains(where: { special.contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func listItem(_ line: String) -> String? {
        let trimmedLead = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLead.count < line.count, trimmedLead.hasPrefix("- ") else { return nil }
        return String(trimmedLead.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }
}
