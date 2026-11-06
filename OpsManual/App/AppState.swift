import SwiftUI
import Observation

enum SidebarSelection: Hashable {
    case all, recent, inbox, drift, parked, category(String)
}

enum EditorTarget: Identifiable, Hashable {
    case new(category: String)
    case edit(id: String, filePath: String? = nil)
    var id: String {
        switch self {
        case .new(let c): "new:\(c)"
        case .edit(let id, let filePath): "edit:\(filePath ?? id)"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var selection: SidebarSelection = .all
    var selectedDocID: String?
    /// The page picked in the Drift list (Drift shows its claims, not the page).
    var driftPageID: String?
    /// The line picked in the Inbox list.
    var inboxReportID: Int?
    /// The What's new sheet's lines while it is open.
    var whatsNew: [WhatsNew.Line]?
    var editorTarget: EditorTarget?
    var isSearchPresented = false
    var trashCandidate: OpsDocument?

    static let recentLimit = 10

    var listTitle: String {
        switch selection {
        case .all: "All Documents"
        case .recent: "Recent"
        case .inbox: "Inbox"
        case .drift: "Drift"
        case .parked: "Parked"
        case .category(let name): name
        }
    }

    func visibleDocuments(in store: DocumentStore) -> [OpsDocument] {
        switch selection {
        case .all: store.activeDocuments
        case .recent: Array(store.activeDocuments.prefix(Self.recentLimit))
        case .parked: store.parkedDocuments
        case .inbox, .drift: []
        case .category(let name): store.activeDocuments.filter { $0.category == name }
        }
    }

    /// Select a document; if it is not in the current list, jump to All Documents first.
    func open(docID: String, in store: DocumentStore) {
        guard let doc = store.document(id: docID) else { return }
        if !visibleDocuments(in: store).contains(where: { $0.id == docID }) {
            selection = doc.isParked ? .parked : .all
        }
        selectedDocID = docID
    }

    func categoryForNewDocument() -> String {
        if case .category(let name) = selection { return name }
        return ""
    }
}
