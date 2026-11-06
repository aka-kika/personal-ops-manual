import SwiftUI
import AppKit

/// Menu bar. The app only reads (2.4.0): no New Document, no Edit.
struct OpsCommands: Commands {
    @Bindable var state: AppState
    let store: DocumentStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Document") {
            Button("Open in Default App") {
                if let doc = selected { NSWorkspace.shared.open(store.fileURL(for: doc)) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(state.selectedDocID == nil)
            Button("Show in Finder") {
                if let doc = selected { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: doc)]) }
            }
            .disabled(state.selectedDocID == nil)
            Divider()
            Button("Search") { state.isSearchPresented = true }.keyboardShortcut("k", modifiers: .command)
            Button("Refresh") { store.load() }.keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(after: .help) {
            Button("What's New in Personal Ops Manual") {
                state.whatsNew = WhatsNew.notes(for: WhatsNew.currentVersion)
            }
            .disabled(WhatsNew.notes(for: WhatsNew.currentVersion) == nil)
        }
    }

    private var selected: OpsDocument? { state.selectedDocID.flatMap { store.document(id: $0) } }
}
