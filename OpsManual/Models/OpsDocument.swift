import Foundation

struct DocProperty: Hashable, Sendable {
    var key: String
    var value: String
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

    static let knownKeys: Set<String> = ["title", "category", "tags", "createdAt", "updatedAt", "id", "summary"]

    var icon: String { properties.first { $0.key == "icon" }?.value ?? "" }
    var updatedDate: Date { FrontmatterCodec.isoFormatter.date(from: updatedAt) ?? .distantPast }
    var createdDate: Date { FrontmatterCodec.isoFormatter.date(from: createdAt) ?? .distantPast }
    var fileName: String { "\(Self.slugify(title))-\(id).md" }

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
