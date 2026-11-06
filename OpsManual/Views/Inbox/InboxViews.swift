import SwiftUI
import AppKit

/// The middle column when Inbox is picked: the open reports in `_inbox/reports.md`,
/// newest first, shown in the app instead of handing the file to another editor.
/// Read only: the operator applies reports and ticks them in the file.
struct InboxListView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState

    var body: some View {
        let reports = store.openInboxReports.reversed() as [InboxReport]
        VStack(spacing: 0) {
            // No corner button: Open in Finder is on the Inbox row's right-click in the sidebar.
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Inbox").font(OpsTheme.titleFont).lineLimit(1)
                    Text(reports.isEmpty ? "No open reports" : reports.count == 1 ? "1 open report" : "\(reports.count) open reports")
                        .font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if reports.isEmpty {
                EmptyState(text: "Nothing waiting for the operator")
            } else {
                let outOfDate = reports.filter(\.outOfDate)
                let readers = reports.filter { !$0.outOfDate }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if !outOfDate.isEmpty {
                            GroupedSection(title: "OUT OF DATE", count: outOfDate.count)
                            rows(outOfDate)
                        }
                        if !readers.isEmpty {
                            GroupedSection(title: "FROM READERS", count: readers.count)
                            rows(readers)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .hidesTopScrollEdgeEffect()
            }
        }
        .background(OpsTheme.canvas)
    }

    private func rows(_ list: [InboxReport]) -> some View {
        ForEach(list) { report in
            InboxRow(report: report, pageTitle: store.document(forReportPage: report.page)?.title,
                     selected: state.inboxReportID == report.id)
                .onTapGesture { state.inboxReportID = report.id }
        }
    }
}

private struct InboxRow: View {
    let report: InboxReport
    let pageTitle: String?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.malformed ? "Typed by hand" : (pageTitle ?? report.page))
                    .font(OpsTheme.rowTitleFont).lineLimit(1)
                Spacer(minLength: 8)
                if let date = report.reportedDate {
                    Text(ListDate.format(date)).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                }
            }
            Text(report.what).font(OpsTheme.excerptFont).foregroundStyle(.secondary).lineLimit(2)
            if !report.agent.isEmpty {
                Text(report.agent).font(OpsTheme.metaFont).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? OpsTheme.selection : .clear))
        .contentShape(Rectangle())
    }
}

/// The detail column for Inbox: one report in full, and a way to its page.
struct InboxDetailView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState

    var body: some View {
        if let id = state.inboxReportID, let report = store.openInboxReports.first(where: { $0.id == id }) {
            reportView(report)
        } else {
            fileView
        }
    }

    /// No line picked: the inbox file itself, rendered like a page (Kika, 2026-11-06:
    /// "a rendered md list of the inbox md file. not too fancy"). Read only.
    private var fileView: some View {
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Inbox").font(OpsTheme.titleFont).lineLimit(1)
                    Text("_inbox/reports.md").font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.inboxMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("The inbox file is empty: no report has been filed yet.").font(OpsTheme.rowFont).foregroundStyle(.tertiary)
                    } else {
                        MarkdownView(markdown: store.inboxMarkdown, baseURL: store.folder)
                    }
                }
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
        }
        .background(OpsTheme.canvas)
    }

    private func reportView(_ report: InboxReport) -> some View {
        let doc = report.malformed ? nil : store.document(forReportPage: report.page)
        return VStack(spacing: 0) {
            // No corner icon: the "Open <page>" button below does the same.
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(report.malformed ? "Typed by hand" : (doc?.title ?? report.page)).font(OpsTheme.titleFont).lineLimit(1)
                    Text(subtitle(report)).font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DriftCard {
                        VStack(alignment: .leading, spacing: 12) {
                            field("WHAT", report.what)
                            if !report.evidence.isEmpty { field("EVIDENCE", report.evidence) }
                            if !report.malformed {
                                if let doc {
                                    Button {
                                        state.open(docID: doc.id, in: store)
                                    } label: {
                                        Label("Open \(doc.title)", systemImage: "doc.text").font(.system(size: 12, weight: .medium))
                                    }
                                    .controlSize(.small)
                                } else {
                                    Text("No page is named \"\(report.page)\".").font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THE LINE IN THE INBOX").font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
                        Text(report.line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OpsTheme.codeBackground))
                    }
                    DriftNote(symbol: "tray", text: report.malformed
                        ? "This line was typed into the inbox by hand, not filed with report_change. The operator checks it like a report, then deletes it."
                        : report.outOfDate
                            ? "Written by the app's check. The operator checks the fact, updates the page and removes the line; once the fact holds again the line goes away by itself."
                            : "Read only. The operator applies what is true to the page, then ticks the line in _inbox/reports.md.")
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
            .id(report.id)
        }
        .background(OpsTheme.canvas)
    }

    private func subtitle(_ report: InboxReport) -> String {
        guard !report.malformed else { return "Not in the report_change shape" }
        var parts = [report.outOfDate ? "Found by the \(report.agent) check" : "Reported by \(report.agent)"]
        if let date = report.reportedDate { parts.append(ReaderDate.format(date)) }
        return parts.joined(separator: " · ")
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
            Text(value).font(OpsTheme.rowFont).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A section label with a count, above the inbox's two groups.
struct GroupedSection: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text(title).font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(OpsTheme.metaFont).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
