import SwiftUI
import AppKit

/// The detail column when a category is picked and no page is: what the category
/// holds and its rules. The rules come from the category's own overview page
/// ("Hooks overview", "App Store index") when it has one; otherwise its pages are listed.
struct CategoryOverviewView: View {
    /// The row's name: a category, or "MCP" for the two MCP categories together.
    let title: String
    let categories: Set<String>
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    /// Set for the GitHub category: its repo summary sits on top.
    var github: GitHubMonitor? = nil

    private var category: String { title }

    /// The overview page among this row's pages: one category's own, else one named after the row ("MCP overview").
    private func overviewPage(_ docs: [OpsDocument]) -> OpsDocument? {
        for name in categories.sorted() {
            if let page = Self.overviewPage(in: docs, category: name) { return page }
        }
        var renamed: [OpsDocument] = []
        for doc in docs {
            var copy = doc
            copy.category = title
            renamed.append(copy)
        }
        guard let found = Self.overviewPage(in: renamed, category: title) else { return nil }
        return docs.first { $0.id == found.id }
    }

    /// The page that describes the category: its title says "overview" or "index".
    static func overviewPage(in docs: [OpsDocument], category: String) -> OpsDocument? {
        let c = category.lowercased()
        var best: OpsDocument?
        var bestScore = Int.max
        for doc in docs where doc.category == category {
            let t = doc.title.lowercased()
            let score: Int
            if t == c + " overview" || t == c + " index" {
                score = 0
            } else if t.hasSuffix(" overview") || t.hasSuffix(" index") {
                score = 1
            } else if t.contains("overview") {
                score = 2
            } else {
                continue
            }
            if score < bestScore || (score == bestScore && doc.title < (best?.title ?? "")) {
                best = doc
                bestScore = score
            }
        }
        return best
    }

    var body: some View {
        let docs = store.activeDocuments.filter { categories.contains($0.category) }
        let overview = overviewPage(docs)
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
            } title: {
                HStack(alignment: .top, spacing: 8) {
                    categoryIcon.padding(.top, 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(category).font(OpsTheme.titleFont).lineLimit(1)
                        Text(subtitle(docs)).font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let github {
                        RepoSummaryCard(docs: docs, github: github, state: state)
                            .padding(.bottom, 18)
                    }
                    if let overview {
                        Text("FROM \(overview.title.uppercased())")
                            .font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
                            .padding(.bottom, 10)
                        if !overview.summary.isEmpty {
                            Text(overview.summary).font(.system(size: 13)).foregroundStyle(.secondary).padding(.bottom, 14)
                        }
                        MarkdownView(markdown: resolved(overview), baseURL: store.folder)
                    } else {
                        Text("PAGES").font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                        ForEach(docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { doc in
                            Button {
                                state.selectedDocID = doc.id
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(doc.title).font(OpsTheme.rowTitleFont)
                                    let excerpt = store.excerpt(for: doc)
                                    if !excerpt.isEmpty {
                                        Text(excerpt).font(OpsTheme.excerptFont).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        DriftNote(symbol: "doc.text",
                                  text: "A page titled \"\(category) overview\" would show here instead: what the category holds and its rules.")
                            .padding(.top, 14)
                    }
                }
                .frame(maxWidth: OpsTheme.readerMaxWidth, alignment: .leading)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
            .id(title)
        }
        .background(OpsTheme.canvas)
        .environment(\.openURL, OpenURLAction { url in
            if let id = WikiLinks.docID(from: url) {
                state.open(docID: id, in: store)
                return .handled
            }
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                return .handled
            }
            return .discarded
        })
    }

    @ViewBuilder
    private var categoryIcon: some View {
        switch title == "MCP" ? CategoryIcons.Icon.symbol("server.rack") : CategoryIcons.icon(for: category) {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 15, weight: .light)).foregroundStyle(.secondary)
        case .asset(let name):
            Image(name).renderingMode(.template).resizable().interpolation(.high)
                .frame(width: 15, height: 15).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ docs: [OpsDocument]) -> String {
        var parts = [docs.count == 1 ? "1 page" : "\(docs.count) pages"]
        if let last = docs.map(\.updatedDate).max(), last > .distantPast {
            parts.append("updated \(ReaderDate.format(last))")
        }
        return parts.joined(separator: " · ")
    }

    private func resolved(_ doc: OpsDocument) -> String {
        let stripped = MarkdownText.stripLeadingTitle(doc.body, title: doc.title)
        return WikiLinks.resolve(stripped) { store.idForTitle($0) }
    }
}
