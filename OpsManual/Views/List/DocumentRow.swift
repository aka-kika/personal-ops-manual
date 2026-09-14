import SwiftUI

struct DocumentRow: View {
    let doc: OpsDocument
    let excerpt: String
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !doc.icon.isEmpty {
                AgentGlyph(name: doc.icon, size: 16).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(doc.title).font(OpsTheme.rowTitleFont).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(ListDate.format(doc.updatedDate)).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                }
                if !excerpt.isEmpty {
                    Text(excerpt).font(OpsTheme.excerptFont).foregroundStyle(.secondary).lineLimit(2)
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
