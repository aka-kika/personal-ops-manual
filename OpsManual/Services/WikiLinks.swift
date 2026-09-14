import Foundation

/// `[[Title]]` and `[[Title|label]]` become in-app links; unresolved titles become plain text.
///
/// Code stays literal. The Node app (doc-viewer.tsx) splits the body on fenced
/// blocks and inline code and transforms only the prose parts, so `[[Title]]`
/// written inside backticks renders as text there; this port does the same.
enum WikiLinks {
    static let scheme = "opsmanual"
    private nonisolated(unsafe) static let pattern = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/
    /// Mirrors Node's /(```[\s\S]*?```|`[^`\n]*`)/ split.
    private nonisolated(unsafe) static let codeSpan = /```[\s\S]*?```|`[^`\n]*`/

    static func url(forDoc id: String) -> URL {
        URL(string: "\(scheme)://doc/\(id)")!
    }

    static func docID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "doc" else { return nil }
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty ? nil : id
    }

    static func linkedTitles(in body: String) -> [String] {
        proseSegments(of: body).flatMap { segment in
            segment.matches(of: pattern).map { String($0.output.1).trimmingCharacters(in: .whitespaces) }
        }
    }

    static func resolve(_ body: String, idForTitle: (String) -> String?) -> String {
        transform(body) { prose in
            String(prose).replacing(pattern) { match in
                let title = String(match.output.1).trimmingCharacters(in: .whitespaces)
                let label = match.output.2.map { String($0).trimmingCharacters(in: .whitespaces) } ?? title
                guard let id = idForTitle(title) else { return label }
                return "[\(label)](\(url(forDoc: id).absoluteString))"
            }
        }
    }

    /// Rebuilds `body` with `prose` applied to every non-code run, code runs kept verbatim.
    private static func transform(_ body: String, prose: (Substring) -> String) -> String {
        var out = ""
        var cursor = body.startIndex
        for match in body.matches(of: codeSpan) {
            out += prose(body[cursor..<match.range.lowerBound])
            out += body[match.range]
            cursor = match.range.upperBound
        }
        out += prose(body[cursor...])
        return out
    }

    private static func proseSegments(of body: String) -> [Substring] {
        var segments: [Substring] = []
        var cursor = body.startIndex
        for match in body.matches(of: codeSpan) {
            segments.append(body[cursor..<match.range.lowerBound])
            cursor = match.range.upperBound
        }
        segments.append(body[cursor...])
        return segments
    }
}
