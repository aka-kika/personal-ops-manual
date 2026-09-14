import SwiftUI

struct SearchPalette: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var focused: Bool

    private var hits: [SearchHit] { store.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search documents", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit(openHighlighted)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { state.isSearchPresented = false; return .handled }
            }
            .padding(14)
            Divider()
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyState(text: "Type to search titles, tags and text").frame(height: 120)
            } else if hits.isEmpty {
                EmptyState(text: "No matches").frame(height: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(hits) { hit in
                                Button { state.open(docID: hit.id, in: store); state.isSearchPresented = false } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(hit.title).font(OpsTheme.rowTitleFont)
                                            Spacer()
                                            Text(hit.category).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                                        }
                                        Text(hit.snippet).font(OpsTheme.excerptFont).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(highlighted == hit.id ? OpsTheme.selection : .clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(hit.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
        .frame(width: 560)
        .background(OpsTheme.canvas)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = hits.first?.id }
    }

    private func move(_ delta: Int) {
        let ids = hits.map(\.id)
        guard !ids.isEmpty else { return }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) } ?? -1
        highlighted = ids[max(0, min(ids.count - 1, current + delta))]
    }

    private func openHighlighted() {
        guard let id = highlighted ?? hits.first?.id else { return }
        state.open(docID: id, in: store)
        state.isSearchPresented = false
    }
}
