import SwiftUI

/// The middle column when Drift is picked: the pages whose claims no longer match
/// this Mac, newest drift first.
struct DriftListView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor

    private var subtitle: String {
        if drift.isChecking && drift.lastChecked == nil { return "Checking…" }
        if drift.results.isEmpty { return "No page states checks yet" }
        let n = drift.driftedPages.count
        if n == 0 { return "Every claim holds" }
        return n == 1 ? "1 page no longer matches this Mac" : "\(n) pages no longer match this Mac"
    }

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Drift").font(OpsTheme.titleFont).lineLimit(1)
                    Text(subtitle).font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if drift.driftedPages.isEmpty {
                EmptyState(text: drift.results.isEmpty ? "Nothing to check" : "No drift")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(drift.driftedPages) { page in
                            DriftPageRow(page: page, selected: state.driftPageID == page.id)
                                .onTapGesture { state.driftPageID = page.id }
                                .contextMenu {
                                    if store.document(id: page.id) != nil {
                                        Button("Open Page") { state.open(docID: page.id, in: store) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .hidesTopScrollEdgeEffect()
            }
        }
        .background(OpsTheme.canvas)
    }
}

private struct DriftPageRow: View {
    let page: DriftPageGroup
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(OpsTheme.peachMark).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(page.title).font(OpsTheme.rowTitleFont).lineLimit(1)
                    Spacer(minLength: 8)
                    if let since = page.results.compactMap(\.driftedSince).max() {
                        Text(ListDate.format(since)).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                    }
                }
                Text(line).font(OpsTheme.excerptFont).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? OpsTheme.selection : .clear))
        .contentShape(Rectangle())
    }

    private var line: String {
        guard let first = page.results.first else { return "" }
        let more = page.results.count - 1
        return more > 0 ? "\(first.summary), and \(more) more" : first.summary
    }
}

struct DriftTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(OpsTheme.codeBackground))
    }
}
