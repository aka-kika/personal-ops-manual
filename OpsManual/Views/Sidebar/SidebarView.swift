import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var hoveringCategories = false

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader(leadingInset: OpsChrome.trafficLightHeaderInset) {
                HeaderChromeButton(systemImage: "magnifyingglass", help: "Search") { state.isSearchPresented = true }
                HeaderChromeButton(systemImage: "gearshape", help: "Settings") { openSettings() }
            } title: {
                navRow(.all, label: "All Documents", font: OpsTheme.titleFont, symbol: nil, count: store.documents.count)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow(.recent, label: "Recent", font: OpsTheme.rowFont, symbol: "clock", count: nil)
                    inboxRow
                    sectionHeader
                    ForEach(store.categories, id: \.name) { cat in
                        navRow(.category(cat.name), label: cat.name, font: OpsTheme.rowFont,
                               symbol: CategoryIcons.symbol(for: cat.name), count: cat.count)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .hidesTopScrollEdgeEffect()
        }
        .background(OpsTheme.sidebarCanvas)
    }

    /// Reports readers filed through the MCP. Opens the inbox file in its editor;
    /// the operator applies what is true and ticks the lines.
    private var inboxRow: some View {
        Button {
            let url = store.inboxFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tray").font(OpsTheme.sidebarIcon).foregroundStyle(.secondary).frame(width: 16)
                Text("Inbox").font(OpsTheme.rowFont).lineLimit(1)
                Spacer(minLength: 4)
                if store.inboxOpenCount > 0 {
                    Text("\(store.inboxOpenCount)").font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reports from readers, in _inbox/reports.md")
    }

    private var sectionHeader: some View {
        HStack {
            Text("CATEGORIES")
                .font(OpsTheme.sectionLabelFont)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer()
            if hoveringCategories {
                Button { state.editorTarget = .new(category: "") } label: {
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

    private func navRow(_ target: SidebarSelection, label: String, font: Font, symbol: String?, count: Int?) -> some View {
        let selected = state.selection == target
        return Button {
            state.selection = target
            state.selectedDocID = nil
        } label: {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(OpsTheme.sidebarIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
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
        .padding(.horizontal, symbol == nil ? -8 : 0)
    }
}
