import SwiftUI
import AppKit

/// The right pane when a category is picked and no page is (Kika, 2026-11-06,
/// mockup category-pane-v4): what lives here, one quiet status line, last changed.
/// No boxes, no tiles: plain text under small grey labels.
struct CategoryPaneView: View {
    /// The row's name: a category, or "MCP" for the two MCP categories together.
    let title: String
    let categories: Set<String>
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor
    var github: GitHubMonitor
    var live: LiveStatusMonitor

    private var docs: [OpsDocument] {
        store.activeDocuments.filter { categories.contains($0.category) && !CategoryOverviewPage.isOverview($0) }
    }

    private var overview: OpsDocument? {
        CategoryOverviewPage.page(for: title, in: store.activeDocuments)
    }

    var body: some View {
        let docs = self.docs
        let status = CategoryStatus.compute(title: title, .init(docs: docs, checkResults: drift.checkResults,
                                                                github: github.snapshot, facts: live.facts))
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(OpsTheme.titleFont).lineLimit(1)
                    Text("Overview").font(OpsTheme.subtitleFont).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let overview {
                        let intro = CategoryOverviewPage.intro(overview)
                        section("WHAT LIVES HERE") {
                            Text(intro.text).font(OpsTheme.rowFont).fixedSize(horizontal: false, vertical: true)
                            if let notHere = intro.notHere {
                                Text(notHere).font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !status.isEmpty {
                        section(status.label) {
                            if let why = status.unavailable, status.parts.isEmpty {
                                Text(why).font(OpsTheme.rowFont).foregroundStyle(.tertiary)
                            } else {
                                statusLine(status.parts)
                                if !status.rows.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(status.rows.enumerated()), id: \.offset) { _, row in
                                            HStack {
                                                Text(row.name).font(OpsTheme.rowFont).lineLimit(1)
                                                Spacer(minLength: 12)
                                                Text(row.value).font(OpsTheme.excerptFont)
                                                    .foregroundStyle(row.attention ? AnyShapeStyle(OpsTheme.peach) : AnyShapeStyle(.tertiary))
                                            }
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                if let why = status.unavailable {
                                    Text(why).font(OpsTheme.excerptFont).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    if !docs.isEmpty {
                        section("LAST CHANGED") {
                            Text(CategoryStatus.lastChanged(docs)).font(OpsTheme.rowFont).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
            .id(title)
        }
        .background(OpsTheme.canvas)
        .task(id: title) {
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            let ids = Set(docs.map(\.id))
            let labels = drift.checkResults.filter { ids.contains($0.pageID) && $0.kind == .launchd }.map(\.subject)
            await live.refreshIfStale(labels: labels)
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
            content()
        }
    }

    /// "3 repos with work not saved · no open pull requests": the number in peach only where it needs care.
    private func statusLine(_ parts: [CategoryStatus.Part]) -> some View {
        var text = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 { text += AttributedString(" · ") }
            var piece = AttributedString(part.text)
            if part.attention, let space = part.text.firstIndex(of: " "),
               let range = piece.range(of: String(part.text[..<space])) {
                piece[range].foregroundColor = OpsTheme.peach
            }
            text += piece
        }
        return Text(text).font(OpsTheme.rowFont).fixedSize(horizontal: false, vertical: true)
    }
}
