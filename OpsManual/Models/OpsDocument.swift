import Foundation

struct DocProperty: Hashable, Sendable {
    var key: String
    var value: String
}

/// A frontmatter key whose value is a YAML list (`checks:` and any other list a
/// hand edit adds). Kept whole so saving a page never drops it.
struct DocListProperty: Hashable, Sendable {
    var key: String
    var items: [String]
}

struct OpsDocument: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var category: String
    var summary: String
    var tags: [String]
    var createdAt: String
    var updatedAt: String
    var properties: [DocProperty]
    var body: String
    var filePath: String = ""
    var listProperties: [DocListProperty] = []

    static let knownKeys: Set<String> = ["title", "category", "tags", "createdAt", "updatedAt", "id", "summary"]
    /// Keys that are always lists, even when a hand edit wrote one value on the key's line.
    static let listKeys: Set<String> = ["checks"]

    /// The Drift lines of this page (`checks:` in the frontmatter), one fact each.
    var checks: [String] { listProperties.first { $0.key == "checks" }?.items ?? [] }

    var icon: String { properties.first { $0.key == "icon" }?.value ?? "" }
    var status: String { properties.first { $0.key == "status" }?.value ?? "" }
    /// `status: parked` or `archived`: kept on disk and in search, out of the category lists.
    var isParked: Bool { ["parked", "archived"].contains(status.trimmingCharacters(in: .whitespaces).lowercased()) }
    var updatedDate: Date { FrontmatterCodec.isoFormatter.date(from: updatedAt) ?? .distantPast }
    var createdDate: Date { FrontmatterCodec.isoFormatter.date(from: createdAt) ?? .distantPast }
    var fileName: String { "\(Self.slugify(title))-\(Self.sanitizeID(id)).md" }

    static func sanitizeID(_ id: String) -> String {
        let cleaned = id
            .replacingOccurrences(of: "..", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// Mirrors the Node app: base36 milliseconds, dash, six base36 chars.
    static func makeID() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let rand = String((0..<6).map { _ in alphabet.randomElement()! })
        return "\(String(ms, radix: 36))-\(rand)"
    }

    /// Mirrors `slugify` in document-store.ts.
    static func slugify(_ text: String) -> String {
        // Node: lowercase, runs of [^a-z0-9] -> "-", trim dashes, slice(0, 60), fallback "untitled".
        var out = ""
        var lastWasDash = false
        for ch in text.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let cut = String(trimmed.prefix(60))
        return cut.isEmpty ? "untitled" : cut
    }
}
