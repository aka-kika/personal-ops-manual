import Foundation

enum MarkdownText {
    /// First line of prose: skips headings, fences, blank lines, tables, rules; strips list markers and inline marks.
    static func excerpt(of body: String) -> String {
        var inFence = false
        for rawLine in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence || line.isEmpty || line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix("---") { continue }
            var text = line.replacing(/^[-*+]\s+|^\d+\.\s+/, with: "")
            text.removeAll { "*_`>[]".contains($0) }
            text = text.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                return text.count > 140 ? String(text.prefix(137)) + "…" : text
            }
        }
        return ""
    }

    /// Mirrors `stripMarkdown` in document-store.ts for search snippets.
    static func strip(_ text: String) -> String {
        var t = text
        t = t.replacing(/```[\s\S]*?```/, with: "")
        t = t.replacing(/`([^`]+)`/) { String($0.output.1) }
        // [[Page|shown]] and [[Page]]: the words only.
        t = t.replacing(/\[\[[^\]|]+\|([^\]]+)\]\]/) { String($0.output.1) }
        t = t.replacing(/\[\[([^\]]+)\]\]/) { String($0.output.1) }
        t = t.replacing(/(?m)^#{1,6}\s+/, with: "")
        t = t.replacing(/\*\*([^*]+)\*\*/) { String($0.output.1) }
        t = t.replacing(/\*([^*]+)\*/) { String($0.output.1) }
        t = t.replacing(/__([^_]+)__/) { String($0.output.1) }
        t = t.replacing(/_([^_]+)_/) { String($0.output.1) }
        t = t.replacing(/!\[([^\]]*)\]\([^)]+\)/) { String($0.output.1) }
        t = t.replacing(/\[([^\]]+)\]\([^)]+\)/) { String($0.output.1) }
        t = t.replacing(/(?m)^[ \t]*[-*+]\s+/, with: "")
        t = t.replacing(/(?m)^[ \t]*\d+\.\s+/, with: "")
        t = t.replacing(/(?m)^>\s+/, with: "")
        t = t.replacing(/(?m)^---+$/, with: "")
        t = t.replacingOccurrences(of: "|", with: " ")
        t = t.replacing(/\n{2,}/, with: "\n")
        t = t.replacing(/\s{2,}/, with: " ")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The reader shows the title in its header, so a leading `# Title` line is dropped.
    static func stripLeadingTitle(_ body: String, title: String) -> String {
        guard let m = body.firstMatch(of: /^\s*#\s+(.+?)\s*\n+/) else { return body }
        guard String(m.output.1).trimmingCharacters(in: .whitespaces).lowercased() == title.trimmingCharacters(in: .whitespaces).lowercased() else { return body }
        return String(body[m.range.upperBound...])
    }
}
