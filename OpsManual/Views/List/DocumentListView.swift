import SwiftUI

struct DocumentListView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var onContextAction: (DocumentContextAction, OpsDocument) -> Void

    var body: some View {
        let docs = state.visibleDocuments(in: store)
        VStack(spacing: 0) {
            ColumnHeader {
                HeaderChromeButton(systemImage: "plus", help: "New Document") {
                    state.editorTarget = .new(category: state.categoryForNewDocument())
                }
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.listTitle).font(OpsTheme.titleFont).lineLimit(1)
                    Text(docs.count == 1 ? "1 document" : "\(docs.count) documents")
                        .font(OpsTheme.subtitleFont).foregroundStyle(.secondary)
                }
            }
            if docs.isEmpty {
                EmptyState(text: store.loadError ?? "No documents")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(docs) { doc in
                            DocumentRow(doc: doc, excerpt: store.excerpt(for: doc), selected: state.selectedDocID == doc.id)
                                .onTapGesture { state.selectedDocID = doc.id }
                                .contextMenu { DocumentContextMenu(doc: doc, action: onContextAction) }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 10)   // air between the header block and the first row
                    .padding(.bottom, 12)
                }
                .hidesTopScrollEdgeEffect()
            }
        }
        .background(OpsTheme.canvas)
    }
}

enum DocumentContextAction { case edit, showInFinder, copyPath, trash }

struct DocumentContextMenu: View {
    let doc: OpsDocument
    let action: (DocumentContextAction, OpsDocument) -> Void
    var body: some View {
        Button("Edit") { action(.edit, doc) }
        Button("Show in Finder") { action(.showInFinder, doc) }
        Button("Copy Path") { action(.copyPath, doc) }
        Divider()
        Button("Move to Trash", role: .destructive) { action(.trash, doc) }
    }
}
