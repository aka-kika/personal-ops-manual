import SwiftUI
import AppKit

// MARK: - Shared list pieces (GitHub and MCP)

/// A small grouped list: section label with a count, then calm one-line rows.
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

struct OneLineRow: View {
    /// nil: no mark (third-party MCP rows stay unmarked).
    let symbol: String?
    let title: String
    var dot = false
    let selected: Bool
    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 14)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            Text(title).font(OpsTheme.rowFont).lineLimit(1)
            if dot {
                Circle().fill(OpsTheme.peachMark).frame(width: 6, height: 6)
                    .help("Work not saved yet")
                    .accessibilityLabel("Work not saved yet")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? OpsTheme.selection : .clear))
        .contentShape(Rectangle())
    }
}

// MARK: - GitHub list

/// The GitHub category: repos grouped Private then Public, names without "(release)",
/// one quiet dot when something is not saved yet. Numbers live on the repo page.
struct GitHubListView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState
    var github: GitHubMonitor

    private struct Groups {
        var priv: [OpsDocument] = []
        var pub: [OpsDocument] = []
        var other: [OpsDocument] = []
    }

    private func groups() -> Groups {
        var g = Groups()
        let docs = state.visibleDocuments(in: store)
            .sorted { GitHubMatcher.displayTitle($0.title).localizedCaseInsensitiveCompare(GitHubMatcher.displayTitle($1.title)) == .orderedAscending }
        for doc in docs {
            switch github.info(for: doc).remote?.visibility {
            case .private?, .internal?: g.priv.append(doc)
            case .public?: g.pub.append(doc)
            case nil: g.other.append(doc)
            }
        }
        return g
    }

    var body: some View {
        let g = groups()
        let repos = g.priv.count + g.pub.count
        let unsaved = (g.priv + g.pub + g.other).filter { github.hasUnsavedWork($0) }.count
        VStack(spacing: 0) {
            ColumnHeader {
                if github.isRefreshing {
                    ProgressView().controlSize(.small).frame(width: OpsChrome.chromeButtonSize, height: OpsChrome.chromeButtonSize)
                }
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("GitHub").font(OpsTheme.titleFont).lineLimit(1)
                    Text(subtitle(pages: g.priv.count + g.pub.count + g.other.count, repos: repos, unsaved: unsaved)).font(OpsTheme.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    section("PRIVATE", g.priv, symbol: "lock")
                    section("PUBLIC", g.pub, symbol: "globe")
                    section("OTHER PAGES", g.other, symbol: "doc.text")
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
            .hidesTopScrollEdgeEffect()
            Spacer(minLength: 0)
            OverviewFooter(title: GitHubMatcher.category, store: store, state: state)
            footer
        }
        .background(OpsTheme.canvas)
    }

    private func subtitle(pages: Int, repos: Int, unsaved: Int) -> String {
        var text = (pages == 1 ? "1 page" : "\(pages) pages") + " · " + (repos == 1 ? "1 repo" : "\(repos) repos")
        if unsaved > 0 { text += " · \(unsaved) \(unsaved == 1 ? "has" : "have") work not saved" }
        return text
    }

    @ViewBuilder
    private func section(_ title: String, _ docs: [OpsDocument], symbol: String) -> some View {
        if !docs.isEmpty {
            GroupedSection(title: title, count: docs.count)
            ForEach(docs) { doc in
                OneLineRow(symbol: symbol, title: GitHubMatcher.displayTitle(doc.title), dot: github.hasUnsavedWork(doc),
                           selected: state.selectedDocID == doc.id)
                    .onTapGesture { state.selectedDocID = doc.id }
                    .contextMenu { PageContextMenu(doc: doc, store: store) }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(OpsTheme.separator).frame(height: 1)
            Text(footerText)
                .font(OpsTheme.metaFont).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
    }

    private var footerText: String {
        guard let at = github.snapshot.refreshedAt else { return "Not refreshed yet · right-click GitHub to refresh" }
        var text = "Refreshed \(ListDate.format(at)) · by gh and local git"
        if let error = github.snapshot.remoteError { text = "Refreshed \(ListDate.format(at)) · GitHub: \(error)" }
        return text
    }
}

// MARK: - Repo card (on top of a GitHub page)

/// What is real now for a GitHub page's repo, shown above the page's own text
/// (Kika, 2026-11-06: "the part we build should live together with the info").
/// Calm: only a row that needs attention gets a mark. Mismatches go to the inbox.
struct RepoCard: View {
    let doc: OpsDocument
    var github: GitHubMonitor

    /// Only for pages the refresh knows something about (not the index or a list page).
    static func applies(_ doc: OpsDocument, github: GitHubMonitor) -> Bool {
        let info = github.info(for: doc)
        return info.remote != nil || info.local != nil
    }

    var body: some View {
        let info = github.info(for: doc)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let remote = info.remote {
                    Label(remote.visibility == .public ? "Public" : "Private",
                          systemImage: remote.visibility == .public ? "globe" : "lock")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(OpsTheme.codeBackground))
                }
                Text(subtitle(info)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            DriftCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows(info).enumerated()), id: \.offset) { index, row in
                        if index > 0 { Rectangle().fill(OpsTheme.separator).frame(height: 1) }
                        RepoFactRow(row: row)
                    }
                }
            }
            if let error = github.snapshot.remoteError {
                DriftNote(symbol: "xmark", text: "GitHub couldn't be checked: \(error). Local git still shows.")
            }
        }
        .padding(.bottom, 18)
    }

    private func subtitle(_ info: GitHubMonitor.Info) -> String {
        var parts: [String] = [info.remote?.nameWithOwner ?? info.key ?? "no repo found"]
        if let at = github.snapshot.refreshedAt { parts.append("refreshed \(ListDate.format(at))") }
        return parts.joined(separator: " · ")
    }

    /// The installed app's version, when the page has an `app` line under checks:.
    private var installedVersion: String? {
        for line in doc.checks {
            if case .success(let check) = DriftCheck.parse(line), check.kind == .app,
               case .installed(_, let version) = DriftProbe().app(check.subject) { return version }
        }
        return nil
    }

    private func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }

    private func rows(_ info: GitHubMonitor.Info) -> [RepoFactRow.Row] {
        var out: [RepoFactRow.Row] = []
        if let local = info.local, local.exists, local.isRepo {
            out.append(.init(symbol: "arrow.triangle.branch", label: "Branch", value: local.branch ?? "unknown",
                             detail: local.upstream.map { "follows \($0)" } ?? "no upstream"))
            let files = local.changedFiles.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                + (local.changedFiles.count > 3 ? ", …" : "")
            out.append(.init(symbol: "doc.text", label: "Uncommitted", value: local.uncommitted == 0 ? "none" : plural(local.uncommitted, "file", "files"),
                             detail: files.isEmpty ? nil : files, attention: local.uncommitted > 0, mono: true))
            out.append(.init(symbol: "arrow.up", label: "Unpushed", value: local.ahead == 0 ? "none" : plural(local.ahead, "commit", "commits"),
                             detail: local.ahead > 0 ? "not on GitHub yet" : nil, attention: local.ahead > 0))
            out.append(.init(symbol: "arrow.down", label: "Behind remote", value: local.behind == 0 ? "none" : plural(local.behind, "commit", "commits"),
                             detail: local.behind > 0 ? "as of the last fetch" : nil, attention: local.behind > 0))
        }
        if let remote = info.remote {
            let installed = installedVersion
            let tagDiffers = installed.map { v in remote.latestTag.map { !DriftEvaluator.sameVersion($0, v) } ?? false } ?? false
            out.append(.init(symbol: "tag", label: "Latest tag", value: remote.latestTag ?? "none",
                             detail: installed.map { "installed app: \($0)" }, attention: tagDiffers, mono: true))
            out.append(.init(symbol: "arrow.triangle.pull", label: "Open PRs", value: remote.openPRs == 0 ? "none" : "\(remote.openPRs)",
                             attention: remote.openPRs > 0))
            out.append(buildRow(remote))
        } else if github.snapshot.remoteError != nil {
            out.append(.init(symbol: "globe", label: "GitHub", value: "couldn't check", dim: true))
        }
        if let local = info.local {
            out.append(.init(symbol: "internaldrive", label: "On this Mac", value: local.path,
                             detail: local.exists ? (local.isRepo ? nil : "not a git folder") : "the folder is missing",
                             attention: !local.exists, mono: true))
        } else {
            out.append(.init(symbol: "internaldrive", label: "On this Mac", value: "no path: line on the page", dim: true))
        }
        return out
    }

    private func buildRow(_ remote: RemoteRepo) -> RepoFactRow.Row {
        let when = remote.ciAt.map { ListDate.format($0) }
        let detail = [remote.ciName, when].compactMap { $0 }.joined(separator: " · ")
        switch remote.ci {
        case .success:
            return .init(symbol: "checkmark.circle", label: "Last build", value: "", detail: detail.isEmpty ? nil : detail, status: .ok)
        case .failure:
            return .init(symbol: "checkmark.circle", label: "Last build", value: "failed", detail: detail.isEmpty ? nil : detail, attention: true)
        case .pending:
            return .init(symbol: "checkmark.circle", label: "Last build", value: "running", detail: detail.isEmpty ? nil : detail)
        case .none:
            return .init(symbol: "checkmark.circle", label: "Last build", value: "no builds", dim: true)
        }
    }
}

struct RepoFactRow: View {
    struct Row {
        enum Status { case plain, ok }
        var symbol: String
        var label: String
        var value: String
        var detail: String? = nil
        var attention = false
        var dim = false
        var mono = false
        var status: Status = .plain
    }
    let row: Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: row.symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
            Text(row.label).font(OpsTheme.rowFont).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if row.status == .ok {
                        // Only the green part (Kika, 2026-11-06): no "Passed", no "green".
                        Image(systemName: "checkmark.circle").font(.system(size: 12)).foregroundStyle(OpsTheme.sage)
                            .accessibilityLabel("Passed")
                    }
                    if !row.value.isEmpty {
                        Text(row.value)
                            .font(row.mono ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                            .foregroundStyle(row.dim ? AnyShapeStyle(.tertiary) : row.attention ? AnyShapeStyle(OpsTheme.peach) : AnyShapeStyle(.primary))
                            .textSelection(.enabled)
                    }
                    if row.status == .ok, let detail = row.detail {
                        Text(detail).font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                    }
                }
                if row.status != .ok, let detail = row.detail {
                    Text(detail).font(.system(size: 11, design: row.mono ? .monospaced : .default)).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if row.attention {
                Circle().fill(OpsTheme.peachMark).frame(width: 6, height: 6).accessibilityLabel("Needs attention")
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - MCP in one row

/// "MCP (mine)" and "MCP (third-party)" as one list, grouped, a small mark on her own servers.
struct MCPListView: View {
    @Bindable var store: DocumentStore
    @Bindable var state: AppState

    var body: some View {
        let docs = state.visibleDocuments(in: store).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let mine = docs.filter { $0.category == MCPGroups.mine }
        let others = docs.filter { $0.category != MCPGroups.mine }
        VStack(spacing: 0) {
            ColumnHeader {
                EmptyView()
            } title: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("MCP").font(OpsTheme.titleFont).lineLimit(1)
                    Text(docs.count == 1 ? "1 server" : "\(docs.count) servers").font(OpsTheme.subtitleFont).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !mine.isEmpty {
                        GroupedSection(title: "MINE", count: mine.count)
                        ForEach(mine) { row($0, symbol: "person.crop.circle") }
                            .help("Mine")
                    }
                    if !others.isEmpty {
                        GroupedSection(title: "THIRD-PARTY", count: others.count)
                        ForEach(others) { row($0, symbol: nil) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
            .hidesTopScrollEdgeEffect()
            Spacer(minLength: 0)
            OverviewFooter(title: "MCP", store: store, state: state)
        }
        .background(OpsTheme.canvas)
    }

    private func row(_ doc: OpsDocument, symbol: String?) -> some View {
        OneLineRow(symbol: symbol, title: doc.title, selected: state.selectedDocID == doc.id)
            .onTapGesture { state.selectedDocID = doc.id }
            .contextMenu { PageContextMenu(doc: doc, store: store) }
    }
}

// MARK: - Overview footer

/// The list column's footer line for a category's overview page ("Overview: Machines overview").
struct OverviewFooter: View {
    let title: String
    @Bindable var store: DocumentStore
    @Bindable var state: AppState

    var body: some View {
        if let page = CategoryOverviewPage.page(for: title, in: store.activeDocuments) {
            VStack(spacing: 0) {
                Rectangle().fill(OpsTheme.separator).frame(height: 1)
                Button {
                    state.selectedDocID = page.id
                } label: {
                    Text("Overview: \(page.title)")
                        .font(OpsTheme.metaFont)
                        .foregroundStyle(state.selectedDocID == page.id ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { PageContextMenu(doc: page, store: store) }
            }
        }
    }
}
