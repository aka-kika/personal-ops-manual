import SwiftUI
import AppKit

struct DocumentListView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState

    var body: some View {
        let docs = state.visibleDocuments(in: store)
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
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
                        ForEach(docs, id: \.filePath) { doc in
                            DocumentRow(doc: doc, excerpt: store.excerpt(for: doc), selected: state.selectedDocID == doc.id)
                                .onTapGesture { state.selectedDocID = doc.id }
                                .contextMenu { PageContextMenu(doc: doc, store: store) }
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

/// Right-click on a page, in a list or on the open page (Kika, 2026-11-06:
/// "open in default app, copy path, refresh"; per category one link on top:
/// "repos: open repo, even if not mine; account: open the site in safari").
/// The app only reads.
struct PageContextMenu: View {
    let doc: OpsDocument
    let store: DocumentStore
    var body: some View {
        switch PageLinks.link(for: doc) {
        case .repo(let url)?:
            Button("Open Repo") { NSWorkspace.shared.open(url) }
            Divider()
        case .site(let url)?:
            Button("Open Site") { PageLinks.openInSafari(url) }
            Divider()
        case nil:
            EmptyView()
        }
        Button("Open in Default App") { NSWorkspace.shared.open(store.fileURL(for: doc)) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.fileURL(for: doc).path, forType: .string)
        }
        Button("Refresh") { store.load() }
    }
}

/// The one link a page's menu offers, by category, from the page's own fields.
enum PageLinks {
    enum Link: Equatable { case repo(URL), site(URL) }

    static let repoCategories: Set<String> = [GitHubMatcher.category, MCPGroups.mine, MCPGroups.thirdParty, "CLI tools"]
    static let siteCategories: Set<String> = ["Accounts", "Domains"]

    static func link(for doc: OpsDocument) -> Link? {
        if repoCategories.contains(doc.category) { return repoURL(doc).map(Link.repo) }
        if siteCategories.contains(doc.category) { return siteURL(doc).map(Link.site) }
        return nil
    }

    /// `repo:` (owner/name or a URL), else the "Source:" line, else the first GitHub repo link on the page.
    static func repoURL(_ doc: OpsDocument) -> URL? {
        if let repo = GitHubMatcher.property(doc, "repo") {
            if repo.hasPrefix("https://") { return URL(string: repo) }
            if GitHubProbe.isRepoName(repo) { return URL(string: "https://github.com/\(repo)") }
        }
        let full = GitHubMatcher.sourceRepo(in: doc.body) ?? GitHubMatcher.firstGitHubRepo(in: doc.body)
        return full.flatMap { URL(string: "https://github.com/\($0)") }
    }

    /// `url:`, else the first https link on the page.
    static func siteURL(_ doc: OpsDocument) -> URL? {
        if let url = GitHubMatcher.property(doc, "url"), url.hasPrefix("http") { return URL(string: url) }
        guard let range = doc.body.range(of: #"https?://[^\s)>\]"'`]+"#, options: .regularExpression) else { return nil }
        return URL(string: String(doc.body[range]))
    }

    /// Accounts open in Safari, not the default browser (Kika).
    static func openInSafari(_ url: URL) {
        if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
