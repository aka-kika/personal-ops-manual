import SwiftUI
import AppKit

struct OpsCommands: Commands {
    @Bindable var state: AppState
    let store: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") { state.editorTarget = .new(category: state.categoryForNewDocument()) }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Document") {
            Button("Edit") { if let id = state.selectedDocID { state.editorTarget = .edit(id: id) } }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(state.selectedDocID == nil)
            Button("Show in Finder") {
                if let id = state.selectedDocID, let doc = store.document(id: id) {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: doc)])
                }
            }
            .disabled(state.selectedDocID == nil)
            Divider()
            Button("Search…") { state.isSearchPresented = true }.keyboardShortcut("k", modifiers: .command)
            Button("Reload Folder") { store.load() }.keyboardShortcut("r", modifiers: .command)
        }
    }
}
