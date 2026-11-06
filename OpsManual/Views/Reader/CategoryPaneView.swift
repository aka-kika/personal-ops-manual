import SwiftUI
import AppKit

/// The right pane when a category is picked and no page is (Kika, 2026-11-06,
/// mockups category-pane-v4 and v5): what lives here, one quiet status line with one
/// small calm visual, last changed. No boxes, no tiles, no big numbers.
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
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Open Overview Page") { state.selectedDocID = overview.id }
                            Divider()
                            PageContextMenu(doc: overview, store: store)
                        }
                    }
                    if !status.isEmpty {
                        section(status.label) {
                            if let why = status.unavailable, status.parts.isEmpty {
                                Text(why).font(OpsTheme.rowFont).foregroundStyle(.tertiary)
                            } else {
                                statusWithVisual(status)
                                if !status.rows.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(status.rows.enumerated()), id: \.offset) { _, row in
                                            HStack {
                                                Text(row.name).font(OpsTheme.rowFont).lineLimit(1)
                                                Spacer(minLength: 12)
                                                Text(row.value).font(OpsTheme.excerptFont)
                                                    .foregroundStyle(row.attention ? AnyShapeStyle(OpsTheme.peach) : AnyShapeStyle(.tertiary))
                                                if let amount = row.amount { SoftBar(amount: amount) }
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

    /// The status sentence with its one visual: the ring left of it, the segments right
    /// of it, the date line under it.
    @ViewBuilder
    private func statusWithVisual(_ status: CategoryStatus) -> some View {
        switch status.visual {
        case .ring(let fine, let attention)?:
            HStack(spacing: 14) {
                StatusRing(fine: fine, attention: attention)
                statusLine(status.parts).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .segments(let on)?:
            HStack(spacing: 14) {
                statusLine(status.parts).frame(maxWidth: .infinity, alignment: .leading)
                StatusSegments(on: on)
            }
        case .dates(let points, let span, let window, let end)?:
            VStack(alignment: .leading, spacing: 12) {
                statusLine(status.parts)
                DateLine(points: points, span: span, window: window, end: end)
            }
        case nil:
            statusLine(status.parts)
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

// MARK: - v5 visuals (small, thin, low contrast; peach only where something needs care)

/// A 40 pt ring, no number inside: sage for what is fine, a short peach arc for the rest.
struct StatusRing: View {
    let fine: Int
    let attention: Int

    var body: some View {
        let total = max(fine + attention, 1)
        let fineShare = CGFloat(fine) / CGFloat(total)
        ZStack {
            Circle().stroke(OpsTheme.codeBackground, lineWidth: 3)
            Circle().trim(from: 0, to: fineShare)
                .stroke(OpsTheme.sageMark.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
            if attention > 0 {
                Circle().trim(from: fineShare, to: 1)
                    .stroke(OpsTheme.peachMark, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 32, height: 32)
        .padding(4)
        .accessibilityElement()
        .accessibilityLabel("\(fine) of \(fine + attention) fine")
    }
}

/// One thin segment per thing: filled sage when fine, a hollow outline when not.
struct StatusSegments: View {
    let on: [Bool]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(on.enumerated()), id: \.offset) { _, isOn in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(OpsTheme.sageMark.opacity(0.75)) : AnyShapeStyle(Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1))
                    .frame(height: 4)
            }
        }
        .frame(width: min(CGFloat(on.count) * 24, 160))
        .accessibilityElement()
        .accessibilityLabel("\(on.filter { $0 }.count) of \(on.count) online")
    }
}

/// A short soft bar after a row's value: how much waits there, against the others.
struct SoftBar: View {
    let amount: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(OpsTheme.codeBackground)
            Capsule().fill(OpsTheme.peachMark.opacity(0.8)).frame(width: 56 * CGFloat(min(max(amount, 0.08), 1)))
        }
        .frame(width: 56, height: 3)
        .padding(.leading, 6)
        .accessibilityHidden(true)
    }
}

/// One hairline from today to the end of the span, a dot per date, the first
/// `window` days a faint band; dots inside it are peach.
struct DateLine: View {
    let points: [CategoryStatus.DatePoint]
    let span: Int
    let window: Int
    let end: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Double) -> CGFloat = { CGFloat(min(max($0 / Double(span), 0), 1)) * w }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(OpsTheme.separator).frame(width: w, height: 1).offset(y: 9)
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(OpsTheme.codeBackground)
                    .frame(width: x(Double(window)), height: 7).offset(y: 6)
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 1, height: 11).offset(y: 4)
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(point.attention ? AnyShapeStyle(OpsTheme.peachMark) : AnyShapeStyle(Color.secondary.opacity(0.55)))
                        .frame(width: 7, height: 7)
                        .offset(x: min(max(x(point.days) - 3.5, 0), w - 7), y: 6)
                        .help(point.name)
                }
                Text("today").offset(y: 16)
                Text("\(window) days").fixedSize().position(x: x(Double(window)), y: 23)
                Text(end).fixedSize().frame(width: w, alignment: .trailing).offset(y: 16)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel(points.map(\.name).joined(separator: ", "))
    }
}
