import SwiftUI
import AppKit

struct ReaderView: View {
    let doc: OpsDocument
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var onAction: (DocumentContextAction, OpsDocument) -> Void
    @AppStorage(AppSettings.showYAMLKey) private var showYAML = false

    /// doc-viewer.tsx: category, "Updated <date>", then the tags when there are any.
    private var subtitle: String {
        var parts = [doc.category, "Updated \(ReaderDate.format(doc.updatedDate))"]
        if !doc.tags.isEmpty { parts.append(doc.tags.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private var resolvedBody: String {
        let stripped = MarkdownText.stripLeadingTitle(doc.body, title: doc.title)
        return WikiLinks.resolve(stripped) { store.idForTitle($0) }
    }

    var body: some View {
        let backlinks = store.backlinks(for: doc.id)
        VStack(spacing: 0) {
            ColumnHeader {
                HeaderChromeButton(systemImage: "pencil", help: "Edit") { onAction(.edit, doc) }
                HeaderChromeButton(systemImage: "folder", help: "Show in Finder") { onAction(.showInFinder, doc) }
                HeaderChromeButton(systemImage: "trash", help: "Move to Trash") { onAction(.trash, doc) }
            } title: {
                HStack(alignment: .top, spacing: 8) {
                    if !doc.icon.isEmpty { AgentGlyph(name: doc.icon, size: 18).padding(.top, 1) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(doc.title).font(OpsTheme.titleFont).lineLimit(1)
                        Text(subtitle)
                            .font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !doc.summary.isEmpty {
                        Text(doc.summary).font(.system(size: 13)).foregroundStyle(.secondary).padding(.bottom, 16)
                    }
                    MarkdownView(markdown: resolvedBody, baseURL: store.folder)
                    if !backlinks.isEmpty {
                        Rectangle().fill(OpsTheme.separator).frame(height: 1).padding(.vertical, 16)
                        Text("Linked from").font(OpsTheme.sectionLabelFont).foregroundStyle(.secondary).padding(.bottom, 6)
                        ForEach(backlinks) { ref in
                            Button {
                                state.open(docID: ref.id, in: store)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(ref.title).font(.system(size: 13)).underline(true, color: Color.secondary.opacity(0.6))
                                    Text(ref.category).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 3)
                        }
                    }
                    FrontmatterDisclosure(doc: doc, showRaw: showYAML)
                }
                .frame(maxWidth: OpsTheme.readerMaxWidth, alignment: .leading)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)   // breathing room between the header block and the page
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
            .id(doc.id)   // reset scroll position per document
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
}
