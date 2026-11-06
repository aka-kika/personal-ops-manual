import SwiftUI

/// One page in a list column: title, date, two-line summary. Every list uses it
/// (Kika, 2026-11-06: "github tab repo list should look like all lists").
struct DocumentRow: View {
    let doc: OpsDocument
    let excerpt: String
    let selected: Bool
    /// A small mark before the name: GitHub's lock or globe, MCP's person for her own servers.
    var symbol: String? = nil
    /// Keep the mark's space when there is no mark, so names line up (third-party MCP).
    var reservesSymbol = false
    /// The quiet dot after the name: work not saved yet.
    var dot = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !doc.icon.isEmpty {
                AgentGlyph(name: doc.icon, size: 16).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 14)
                    } else if reservesSymbol {
                        Color.clear.frame(width: 14, height: 1)
                    }
                    Text(doc.title).font(OpsTheme.rowTitleFont).lineLimit(1)
                    if dot {
                        Circle().fill(OpsTheme.peachMark).frame(width: 6, height: 6)
                            .help("Work not saved yet")
                            .accessibilityLabel("Work not saved yet")
                    }
                    Spacer(minLength: 8)
                    Text(ListDate.format(doc.updatedDate)).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                }
                if !excerpt.isEmpty {
                    Text(excerpt).font(OpsTheme.excerptFont).foregroundStyle(.secondary).lineLimit(2)
                        .padding(.leading, symbol != nil || reservesSymbol ? 20 : 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? OpsTheme.selection : .clear))
        .contentShape(Rectangle())
    }
}
