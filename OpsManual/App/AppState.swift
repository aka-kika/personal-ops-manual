import SwiftUI
import Observation

enum SidebarSelection: Hashable {
    case all, recent, category(String)
}

enum EditorTarget: Identifiable, Hashable {
    case new(category: String)
    case edit(id: String)
    var id: String {
        switch self {
        case .new(let c): "new:\(c)"
        case .edit(let id): "edit:\(id)"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var selection: SidebarSelection = .all
    var selectedDocID: String?
    var editorTarget: EditorTarget?
    var isSearchPresented = false
    var trashCandidate: OpsDocument?

    static let recentLimit = 10

    var listTitle: String {
        switch selection {
        case .all: "All Documents"
        case .recent: "Recent"
        case .category(let name): name
        }
    }

    func visibleDocuments(in store: DocumentStore) -> [OpsDocument] {
        switch selection {
        case .all: store.documents
        case .recent: Array(store.documents.prefix(Self.recentLimit))
        case .category(let name): store.documents.filter { $0.category == name }
        }
    }

    /// Select a document; if it is not in the current list, jump to All Documents first.
    func open(docID: String, in store: DocumentStore) {
        guard store.document(id: docID) != nil else { return }
        if !visibleDocuments(in: store).contains(where: { $0.id == docID }) {
            selection = .all
        }
        selectedDocID = docID
    }

    func categoryForNewDocument() -> String {
        if case .category(let name) = selection { return name }
        return ""
    }
}
