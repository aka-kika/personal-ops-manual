import SwiftUI

struct FrontmatterDisclosure: View {
    let doc: OpsDocument
    let showRaw: Bool
    @State private var expanded = false

    private var rows: [(String, String)] {
        var r: [(String, String)] = [
            ("title", doc.title), ("category", doc.category),
        ]
        if !doc.summary.isEmpty { r.append(("summary", doc.summary)) }
        r.append(("tags", doc.tags.isEmpty ? "[]" : doc.tags.joined(separator: ", ")))
        r.append(("createdAt", doc.createdAt))
        r.append(("updatedAt", doc.updatedAt))
        r.append(("id", doc.id))
        r += doc.properties.map { ($0.key, $0.value) }
        return r
    }

    /// The frontmatter block including its closing `---` fence, exactly as written to disk.
    private var rawFrontmatter: String {
        let serialized = FrontmatterCodec.serialize(doc)
        guard let close = serialized.range(of: "\n---\n", range: serialized.index(serialized.startIndex, offsetBy: 4)..<serialized.endIndex) else {
            return serialized
        }
        return String(serialized[serialized.startIndex..<close.upperBound]).trimmingCharacters(in: .newlines)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                if showRaw {
                    Text(rawFrontmatter)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(OpsTheme.codeBackground))
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.0).font(OpsTheme.metaFont).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                            Text(row.1).font(OpsTheme.excerptFont).textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Frontmatter").font(OpsTheme.metaFont).foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }
}
