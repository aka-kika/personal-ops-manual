import SwiftUI
import Observation

enum SidebarSelection: Hashable {
    case all, recent, inbox, drift, parked, mcp, category(String)
}

/// What the window shows. The app only reads (2.4.0): no editor, no new page, no trash.
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
    var isSearchPresented = false

    static let recentLimit = 10

    var listTitle: String {
        switch selection {
        case .all: "All Documents"
        case .recent: "Recent"
        case .inbox: "Inbox"
        case .drift: "Drift"
        case .parked: "Parked"
        case .mcp: "MCP"
        case .category(let name): name
        }
    }

    var isGitHub: Bool { selection == .category(GitHubMatcher.category) }

    /// A sidebar row was picked: nothing stays selected inside the old list.
    func select(_ target: SidebarSelection) {
        selection = target
        selectedDocID = nil
        driftPageID = nil
        inboxReportID = nil
    }

    func visibleDocuments(in store: DocumentStore) -> [OpsDocument] {
        switch selection {
        case .all: store.activeDocuments
        case .recent: Array(store.activeDocuments.prefix(Self.recentLimit))
        case .parked: store.parkedDocuments
        case .inbox, .drift: []
        case .mcp: store.activeDocuments.filter { MCPGroups.categories.contains($0.category) && !CategoryOverviewPage.isOverview($0) }
        case .category(let name): store.activeDocuments.filter { $0.category == name && !CategoryOverviewPage.isOverview($0) }
        }
    }

    /// Select a document; if it is not in the current list, jump to All Documents (or Parked) first.
    func open(docID: String, in store: DocumentStore) {
        guard let doc = store.document(id: docID) else { return }
        // An overview page opens from its category's footer, so it may stay in that list.
        if !visibleDocuments(in: store).contains(where: { $0.id == docID }), !CategoryOverviewPage.isOverview(doc) {
            selection = doc.isParked ? .parked : .all
        }
        selectedDocID = docID
    }
}
