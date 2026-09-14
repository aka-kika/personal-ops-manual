import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, state: state)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                .titleBarColumn()
        } content: {
            HStack(spacing: 0) {
                columnDivider
                DocumentListView(store: store, state: state, onContextAction: handle)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 460)
            .titleBarColumn()
        } detail: { detailColumn }
        .navigationSplitViewStyle(.balanced)
        .background(OpsTheme.canvas)
        .background(MainWindowChromeConfigurator())
        .frame(minWidth: 900, minHeight: 560)
        .sheet(item: $state.editorTarget) { target in
            DocumentEditorSheet(target: target, store: store) { createdID in
                state.editorTarget = nil
                if let createdID { state.open(docID: createdID, in: store) }
            }
        }
        .alert("Move \"\(state.trashCandidate?.title ?? "")\" to Trash?", isPresented: Binding(
            get: { state.trashCandidate != nil }, set: { if !$0 { state.trashCandidate = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let doc = state.trashCandidate {
                    try? store.trash(id: doc.id)
                    if state.selectedDocID == doc.id { state.selectedDocID = nil }
                }
                state.trashCandidate = nil
            }
            Button("Cancel", role: .cancel) { state.trashCandidate = nil }
        } message: {
            Text("The file goes to the Finder Trash and can be put back.")
        }
        .overlay {
            // A floating palette instead of a sheet: a click outside closes it, Escape too.
            if state.isSearchPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { state.isSearchPresented = false }
                    SearchPalette(store: store, state: state)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OpsTheme.separator))
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                        .padding(.top, 72)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.isSearchPresented)
    }

    /// The split view's own divider after the sidebar is swallowed by the merged
    /// title-bar chrome; draw the same hairline the system draws between the
    /// other two columns so every column boundary looks identical.
    private var columnDivider: some View {
        Rectangle()
            .fill(OpsTheme.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = state.selectedDocID, let doc = store.document(id: id) {
            ReaderView(doc: doc, store: store, state: state, onAction: handle).titleBarColumn()
        } else {
            EmptyState(text: "Select a document").titleBarColumn()
        }
    }

    func handle(_ action: DocumentContextAction, _ doc: OpsDocument) {
        switch action {
        case .edit: state.editorTarget = .edit(id: doc.id)
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: doc)])
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.fileURL(for: doc).path, forType: .string)
        case .trash: state.trashCandidate = doc
        }
    }
}
