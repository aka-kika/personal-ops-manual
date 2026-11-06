import SwiftUI

/// The detail column when Drift is picked: the overview, or one page's claims.
struct DriftDetailView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor

    var body: some View {
        if let id = state.driftPageID, !drift.results(forPage: id).isEmpty {
            DriftPageView(pageID: id, store: store, state: state, drift: drift)
        } else {
            DriftOverviewView(store: store, drift: drift)
        }
    }
}

// MARK: - Overview: the score and what drags it down
//
// The score card and the "what drags it down" list follow the Health page of Cortex
// (github.com/envibagus/cortex, MIT): ideas only, no code copied.

struct DriftOverviewView: View {
    @Bindable var store: DocumentStore
    var drift: DriftMonitor

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Drift").font(OpsTheme.titleFont).lineLimit(1)
                    Text("What the pages claim, checked against this Mac")
                        .font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if drift.results.isEmpty {
                        noChecksCard
                    } else {
                        scoreCard
                        factorsCard
                    }
                    notes
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
        }
        .background(OpsTheme.canvas)
    }

    private var checked: Int { drift.holdsCount + drift.driftedCount }

    private var verdict: String {
        guard checked > 0 else { return "Nothing could be checked" }
        let share = Double(drift.holdsCount) / Double(checked)
        if share >= 1 { return "All true" }
        if share >= 0.9 { return "Mostly true" }
        if share >= 0.6 { return "Partly true" }
        return "Out of date"
    }

    private var scoreCard: some View {
        DriftCard {
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(checked == 0 ? OpsTheme.codeBackground : OpsTheme.peachMark, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: checked == 0 ? 0 : CGFloat(drift.holdsCount) / CGFloat(checked))
                        .stroke(OpsTheme.sageMark, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(drift.holdsCount)").font(.system(size: 22, weight: .semibold))
                        Text("of \(checked)").font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 88, height: 88)
                .padding(4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verdict).font(.system(size: 17, weight: .semibold))
                    Text(scoreText).font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var scoreText: String {
        var parts = ["\(drift.holdsCount) of \(checked) claims still hold."]
        let pages = drift.driftedPages.count
        if pages > 0 { parts.append(pages == 1 ? "1 page drifted." : "\(pages) pages drifted.") }
        var text = parts.joined(separator: " ")
        if let last = drift.lastChecked {
            text += "\nChecked \(ReaderDate.format(last))"
            if let d = drift.lastDuration { text += ", took \(d < 1 ? "under a second" : "\(Int(d.rounded())) seconds")" }
            text += "."
        }
        return text
    }

    private struct Factor: Identifiable {
        var id: String { title }
        let title: String
        let symbol: String
        let pages: Int
    }

    private var factors: [Factor] {
        var groups: [String: (symbol: String, pages: Set<String>, any: Bool)] = [:]
        var order: [String] = []
        for kind in DriftCheck.Kind.allCases where groups[kind.groupTitle] == nil {
            groups[kind.groupTitle] = (kind.symbol, [], false)
            order.append(kind.groupTitle)
        }
        for r in drift.results {
            // A claim that couldn't be checked says nothing about its group.
            guard let kind = r.kind, r.status != .unknown else { continue }
            groups[kind.groupTitle]?.any = true
            if r.status == .drifted { groups[kind.groupTitle]?.pages.insert(r.pageID) }
        }
        return order.compactMap { title in
            guard let g = groups[title], g.any else { return nil }
            return Factor(title: title, symbol: g.symbol, pages: g.pages.count)
        }
        .sorted { $0.pages > $1.pages }
    }

    private var factorsCard: some View {
        let list = factors
        let top = max(list.map(\.pages).max() ?? 0, 1)
        return DriftCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("WHAT DRAGS IT DOWN").font(OpsTheme.sectionLabelFont).tracking(0.5).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(Array(list.enumerated()), id: \.element.id) { index, factor in
                    if index > 0 { Rectangle().fill(OpsTheme.separator).frame(height: 1) }
                    HStack(spacing: 10) {
                        Image(systemName: factor.symbol).font(OpsTheme.sidebarIcon).foregroundStyle(.secondary).frame(width: 16)
                        Text(factor.title).font(OpsTheme.rowFont)
                        Spacer(minLength: 12)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(OpsTheme.codeBackground)
                                Capsule().fill(OpsTheme.peachMark)
                                    .frame(width: geo.size.width * CGFloat(factor.pages) / CGFloat(top))
                            }
                        }
                        .frame(width: 150, height: 5)
                        Text(factor.pages == 0 ? "all hold" : factor.pages == 1 ? "1 page" : "\(factor.pages) pages")
                            .font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var noChecksCard: some View {
        DriftCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No page states checks yet").font(.system(size: 15, weight: .semibold))
                Text("A page lists facts this Mac can confirm under checks: in its frontmatter, one per line, for example port 4319 node. The operator adds them when it verifies a page. Drift then compares each line with this Mac and lists the pages that no longer match.")
                    .font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("app \"Personal Ops Manual\" 2.3.0 notarized\nmcp personal-ops-manual\nport 4319 node\nlaunchd com.akakika.socials\ncli gh 2.103.3")
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OpsTheme.codeBackground))
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        let withChecks = Set(drift.results.map(\.pageID)).count
        let without = max(store.activeDocuments.count - withChecks, 0)
        if !drift.results.isEmpty && without > 0 {
            DriftNote(symbol: "doc.text", text: "\(without) \(without == 1 ? "page says" : "pages say") nothing checkable yet. The operator adds checks: to a page when it verifies it.")
        }
        let unknown = drift.unknown
        if !unknown.isEmpty {
            let first = unknown[0]
            let more = unknown.count > 1 ? " (and \(unknown.count - 1) more)" : ""
            DriftNote(symbol: "xmark",
                      text: "\(unknown.count) \(unknown.count == 1 ? "check" : "checks") couldn't run: \(first.pageTitle), \(first.claim.lowercased()): \(first.now)\(more). Not counted as drift.")
        }
        if let error = drift.reportError {
            DriftNote(symbol: "exclamationmark.triangle", text: error)
        }
    }
}

// MARK: - One page: each claim, what is real now, and Report

struct DriftPageView: View {
    let pageID: String
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var drift: DriftMonitor

    var body: some View {
        let results = drift.results(forPage: pageID)
        let doc = store.document(id: pageID)
        let title = doc?.title ?? results.first?.pageTitle ?? ""
        VStack(spacing: 0) {
            ColumnHeader {
                if doc != nil {
                    HeaderChromeButton(systemImage: "doc.text", help: "Open Page") { state.open(docID: pageID, in: store) }
                }
                if drift.isChecking {
                    ProgressView().controlSize(.small).frame(width: OpsChrome.chromeButtonSize, height: OpsChrome.chromeButtonSize)
                } else {
                    HeaderChromeButton(systemImage: "arrow.clockwise", help: "Check Again") {
                        Task { await drift.check(DriftMonitor.pages(from: store.documents)) }
                    }
                }
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(OpsTheme.titleFont).lineLimit(1)
                    Text(subtitle(results, doc: doc)).font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DriftCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ClaimGrid.header
                            ForEach(results) { result in
                                Rectangle().fill(OpsTheme.separator).frame(height: 1)
                                ClaimRow(result: result,
                                         reportedAt: drift.reportDate(result, in: store.inboxReports),
                                         isReported: drift.isReported(result, in: store.inboxReports)) {
                                    drift.report(result, inboxURL: store.inboxFileURL)
                                    store.load()
                                }
                            }
                        }
                    }
                    if let error = drift.reportError {
                        DriftNote(symbol: "exclamationmark.triangle", text: error)
                    }
                    DriftNote(symbol: "doc.text", text: "Read only. Drift never edits a page; Report adds one line to the Inbox for the operator.")
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hidesTopScrollEdgeEffect()
            .id(pageID)
        }
        .background(OpsTheme.canvas)
    }

    private func subtitle(_ results: [DriftResult], doc: OpsDocument?) -> String {
        var parts: [String] = []
        if let doc { parts.append(doc.category) }
        let drifted = results.filter { $0.status == .drifted }.count
        parts.append("\(results.count) \(results.count == 1 ? "check" : "checks"), \(drifted) drifted")
        if let at = results.map(\.checkedAt).max() { parts.append("checked \(ListDate.format(at))") }
        return parts.joined(separator: " · ")
    }
}

private enum ClaimGrid {
    static let says: CGFloat = 96
    static let now: CGFloat = 120
    static let action: CGFloat = 84

    static var header: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 14, height: 1)
            Text("Claim").frame(maxWidth: .infinity, alignment: .leading)
            Text("Page says").frame(width: says, alignment: .leading)
            Text("Now").frame(width: now, alignment: .leading)
            Color.clear.frame(width: action, height: 1)
        }
        .font(OpsTheme.metaFont)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 6)
    }
}

private struct ClaimRow: View {
    let result: DriftResult
    let reportedAt: Date?
    let isReported: Bool
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                mark
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.claim).font(OpsTheme.rowFont)
                    Text(result.subject).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(result.pageSays).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(width: ClaimGrid.says, alignment: .leading)
                Text(result.now)
                    .font(.system(size: 12.5, weight: result.status == .drifted ? .medium : .regular))
                    .foregroundStyle(nowStyle)
                    .lineLimit(3).frame(width: ClaimGrid.now, alignment: .leading)
                    .help(result.now)
                action.frame(width: ClaimGrid.action, alignment: .trailing)
            }
            if isReported, result.status == .drifted {
                Text("\(Text(filedLabel)) \(Text(result.reportWhat).foregroundStyle(.primary))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OpsTheme.codeBackground))
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 10)
    }

    private var filedLabel: String {
        if let reportedAt { return "Filed to the Inbox at \(ListDate.format(reportedAt)):" }
        return "Filed to the Inbox:"
    }

    private var nowStyle: AnyShapeStyle {
        switch result.status {
        case .drifted: AnyShapeStyle(OpsTheme.peach)
        case .holds: AnyShapeStyle(.primary)
        case .unknown: AnyShapeStyle(.tertiary)
        }
    }

    private var markSymbol: String {
        switch result.status {
        case .holds: "checkmark"
        case .drifted: "xmark"
        case .unknown: "questionmark"
        }
    }

    private var markFill: Color {
        switch result.status {
        case .holds: OpsTheme.sageFill
        case .drifted: OpsTheme.peachFill
        case .unknown: OpsTheme.codeBackground
        }
    }

    private var markTint: Color {
        switch result.status {
        case .holds: OpsTheme.sage
        case .drifted: OpsTheme.peach
        case .unknown: Color.secondary
        }
    }

    @ViewBuilder
    private var mark: some View {
        Image(systemName: markSymbol)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(markTint)
            .frame(width: 14, height: 14)
            .background(Circle().fill(markFill))
            .help(result.status == .unknown ? "Couldn't check: \(result.now)" : result.source)
    }

    @ViewBuilder
    private var action: some View {
        if result.status == .drifted {
            if isReported {
                DriftTag(text: "Reported")
            } else {
                Button(action: onReport) {
                    Label("Report", systemImage: "paperplane").font(.system(size: 12, weight: .medium))
                }
                .controlSize(.small)
                .help("Add one line to the Inbox for the operator: \(result.reportWhat)")
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

// MARK: - Shared pieces

struct DriftCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(OpsTheme.separator))
    }
}

struct DriftNote: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(text).font(OpsTheme.excerptFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
