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
            ColumnHeader {
                HeaderChromeButton(systemImage: "folder", help: "Show the Inbox File in Finder") {
                    let url = store.inboxFileURL
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
                    }
                }
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
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(reports) { report in
                            InboxRow(report: report, pageTitle: store.document(forReportPage: report.page)?.title,
                                     selected: state.inboxReportID == report.id)
                                .onTapGesture { state.inboxReportID = report.id }
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
            EmptyState(text: store.openInboxReports.isEmpty ? "No open reports" : "Select a report").background(OpsTheme.canvas)
        }
    }

    private func reportView(_ report: InboxReport) -> some View {
        let doc = report.malformed ? nil : store.document(forReportPage: report.page)
        return VStack(spacing: 0) {
            ColumnHeader {
                if let doc {
                    HeaderChromeButton(systemImage: "doc.text", help: "Open Page") { state.open(docID: doc.id, in: store) }
                }
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
        var parts = ["Reported by \(report.agent)"]
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
