import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor
    var github: GitHubMonitor
    var live: LiveStatusMonitor
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, state: state, drift: drift, github: github)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                .titleBarColumn()
        } content: {
            HStack(spacing: 0) {
                columnDivider
                contentColumn
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 460)
            .titleBarColumn()
        } detail: { detailColumn }
        .navigationSplitViewStyle(.balanced)
        .background(OpsTheme.canvas)
        .background(MainWindowChromeConfigurator())
        .background(TitlebarOverlayGuard(dismiss: state.isSearchPresented ? { state.isSearchPresented = false } : nil))
        .frame(minWidth: 900, minHeight: 560)
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
        .task {
            // Under unit tests the app is only the tests' host: no checks, no sheet, and
            // nothing written to the real settings (What's new would count as seen).
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            drift.startSchedule { [store] in DriftMonitor.pages(from: store.documents) }
            github.startSchedule(documents: { [store] in store.documents }, interval: { [drift] in drift.interval })
            if WhatsNew.shouldShow() { state.whatsNew = WhatsNew.notes(for: WhatsNew.currentVersion) }
        }
        .onChange(of: state.selection) { _, selection in
            // Opening Drift checks right away (the timer only covers the rest of the day).
            if selection == .drift { Task { await drift.check(DriftMonitor.pages(from: store.documents)) } }
        }
        .onChange(of: store.documents) { _, docs in
            drift.prune(keeping: Set(docs.filter { !$0.checks.isEmpty && !$0.isParked }.map(\.id)))
            drift.setRepoResults(github.driftResults(for: docs))
        }
        .onChange(of: github.snapshot.refreshedAt) { _, _ in
            drift.setRepoResults(github.driftResults(for: store.documents))
            let sections = InboxSync.sections(checks: drift.checkResults, repo: drift.repoResults, githubRead: github.remoteKnown)
            syncInbox(github: sections.github, mac: sections.mac)
        }
        .onChange(of: drift.lastChecked) { _, _ in
            let sections = InboxSync.sections(checks: drift.checkResults, repo: drift.repoResults, githubRead: false)
            syncInbox(github: sections.github, mac: sections.mac)
        }
        .sheet(isPresented: Binding(get: { state.whatsNew != nil }, set: { if !$0 { state.whatsNew = nil; WhatsNew.markSeen() } })) {
            WhatsNewSheet(appName: "Personal Ops Manual", lines: state.whatsNew ?? []) {
                state.whatsNew = nil
                WhatsNew.markSeen()
            }
        }
    }

    /// What is out of date goes into the inbox by itself (never under unit tests).
    private func syncInbox(github: [InboxSync.Finding]?, mac: [InboxSync.Finding]?) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        _ = try? InboxSync.write(github: github, mac: mac, inboxURL: store.inboxFileURL)
        store.load()
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch state.selection {
        case .drift: DriftListView(store: store, state: state, drift: drift)
        case .inbox: InboxListView(store: store, state: state)
        case .mcp: MCPListView(store: store, state: state)
        case .category(GitHubMatcher.category): GitHubListView(store: store, state: state, github: github)
        default: DocumentListView(store: store, state: state)
        }
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
        if state.selection == .drift && state.selectedDocID == nil {
            DriftDetailView(store: store, state: state, drift: drift, github: github).titleBarColumn()
        } else if state.selection == .inbox && state.selectedDocID == nil {
            InboxDetailView(store: store, state: state).titleBarColumn()
        } else if let id = state.selectedDocID, let doc = store.document(id: id) {
            ReaderView(doc: doc, store: store, state: state, github: github).titleBarColumn()
        } else if state.selection == .mcp {
            CategoryPaneView(title: "MCP", categories: MCPGroups.categories, store: store, state: state,
                             drift: drift, github: github, live: live).titleBarColumn()
        } else if case .category(let name) = state.selection {
            CategoryPaneView(title: name, categories: [name], store: store, state: state,
                             drift: drift, github: github, live: live).titleBarColumn()
        } else {
            EmptyState(text: "Select a document").titleBarColumn()
        }
    }

}
