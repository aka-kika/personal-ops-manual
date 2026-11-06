import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor
    var github: GitHubMonitor

    /// One sidebar row per category, except the two MCP categories, which share one "MCP" row.
    private enum Row: Identifiable {
        case category(String, Int)
        case mcp(Int)
        var id: String {
            switch self {
            case .category(let name, _): name
            case .mcp: "MCP"
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        var mcpCount = 0
        var mcpIndex: Int?
        for cat in store.categories {
            if MCPGroups.categories.contains(cat.name) {
                mcpCount += cat.count
                if mcpIndex == nil { mcpIndex = out.count; out.append(.mcp(0)) }
            } else {
                out.append(.category(cat.name, cat.count))
            }
        }
        if let mcpIndex { out[mcpIndex] = .mcp(mcpCount) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search is Cmd-K and Settings is in the app menu (Kika, 2026-11-06): no buttons here.
            ColumnHeader(leadingInset: OpsChrome.trafficLightHeaderInset) {
                EmptyView()
            } title: {
                navRow(.all, label: "All Documents", font: OpsTheme.titleFont, icon: nil, count: store.activeDocuments.count)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow(.recent, label: "Recent", font: OpsTheme.rowFont, icon: .symbol("clock"), count: nil)
                    navRow(.inbox, label: "Inbox", font: OpsTheme.rowFont, icon: .symbol("tray"),
                           count: store.inboxOpenCount > 0 ? store.inboxOpenCount : nil)
                        .help("Reports from readers, in _inbox/reports.md")
                    navRow(.drift, label: "Drift", font: OpsTheme.rowFont, icon: .symbol("gauge.with.dots.needle.67percent"),
                           count: drift.driftedPages.isEmpty ? nil : drift.driftedPages.count)
                        .help("Pages whose claims no longer match this Mac")
                        .contextMenu {
                            Button("Check Now") { Task { await drift.check(DriftMonitor.pages(from: store.documents)) } }
                                .disabled(drift.isChecking)
                        }
                    sectionHeader
                    ForEach(rows) { row in
                        switch row {
                        case .mcp(let count):
                            navRow(.mcp, label: "MCP", font: OpsTheme.rowFont, icon: .symbol("server.rack"), count: count)
                        case .category(let name, let count):
                            if name == GitHubMatcher.category {
                                navRow(.category(name), label: name, font: OpsTheme.rowFont,
                                       icon: CategoryIcons.icon(for: name), count: count)
                                    .contextMenu { githubMenu }
                            } else {
                                navRow(.category(name), label: name, font: OpsTheme.rowFont,
                                       icon: CategoryIcons.icon(for: name), count: count)
                            }
                        }
                    }
                    if !store.parkedDocuments.isEmpty {
                        // Parked and archived pages: one quiet row at the bottom.
                        navRow(.parked, label: "Parked", font: OpsTheme.rowFont, icon: .symbol("archivebox"),
                               count: store.parkedDocuments.count)
                            .opacity(state.selection == .parked ? 1 : 0.6)
                            .padding(.top, 10)
                            .help("Pages with status parked or archived")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .hidesTopScrollEdgeEffect()
        }
        .background(OpsTheme.sidebarCanvas)
    }

    /// Kika's words, in her order: "refresh, copy path, open github".
    @ViewBuilder
    private var githubMenu: some View {
        Button("Refresh") {
            Task {
                await github.refresh(store.documents)
                drift.setRepoResults(github.driftResults(for: store.documents))
            }
        }
        .disabled(github.isRefreshing)
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.folder.path, forType: .string)
        }
        Button("Open on GitHub") {
            let login = github.snapshot.login ?? ""
            if let url = URL(string: "https://github.com/\(login)") { NSWorkspace.shared.open(url) }
        }
    }

    private var sectionHeader: some View {
        Text("CATEGORIES")
            .font(OpsTheme.sectionLabelFont)
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func navRow(_ target: SidebarSelection, label: String, font: Font, icon: CategoryIcons.Icon?, count: Int?) -> some View {
        let selected = state.selection == target
        return Button {
            state.select(target)
        } label: {
            HStack(spacing: 8) {
                switch icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(OpsTheme.sidebarIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                case .asset(let name):
                    Image(name).renderingMode(.template).resizable().interpolation(.high)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                case nil:
                    EmptyView()
                }
                Text(label).font(font).lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)").font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? OpsTheme.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, icon == nil ? -8 : 0)
    }
}

/// The two MCP categories shown as one sidebar row (Kika, 2026-11-06). The categories
/// stay as they are on disk; the group comes from each page's category.
enum MCPGroups {
    static let mine = "MCP (mine)"
    static let thirdParty = "MCP (third-party)"
    static let categories: Set<String> = [mine, thirdParty]
}
