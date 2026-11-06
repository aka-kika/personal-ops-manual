import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor
    @Environment(\.openSettings) private var openSettings
    @State private var hoveringCategories = false

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(leadingInset: OpsChrome.trafficLightHeaderInset) {
                HeaderChromeButton(systemImage: "magnifyingglass", help: "Search") { state.isSearchPresented = true }
                HeaderChromeButton(systemImage: "gearshape", help: "Settings") { openSettings() }
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
                    sectionHeader
                    ForEach(store.categories, id: \.name) { cat in
                        navRow(.category(cat.name), label: cat.name, font: OpsTheme.rowFont,
                               icon: CategoryIcons.icon(for: cat.name), count: cat.count)
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

    private var sectionHeader: some View {
        HStack {
            Text("CATEGORIES")
                .font(OpsTheme.sectionLabelFont)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer()
            if hoveringCategories {
                Button { state.editorTarget = .new(category: "__new__") } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Category")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onHover { hoveringCategories = $0 }
    }

    private func navRow(_ target: SidebarSelection, label: String, font: Font, icon: CategoryIcons.Icon?, count: Int?) -> some View {
        let selected = state.selection == target
        return Button {
            state.selection = target
            state.selectedDocID = nil
            state.driftPageID = nil
            state.inboxReportID = nil
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
