import SwiftUI
import AppKit
import Markdown

struct MarkdownBlockView: View {
    let block: any BlockMarkup
    var baseURL: URL?

    var body: some View {
        switch block {
        case let h as Heading:
            SwiftUI.Text(MarkdownInline.attributed(h))
                .font(.system(size: headingSize(h.level), weight: .semibold))
                .padding(.top, headingTop(h.level))
                .padding(.bottom, 6)
                .textSelection(.enabled)
        case let p as Paragraph where p.childCount == 1 && p.child(at: 0) is Markdown.Image:
            ImageBlock(image: p.child(at: 0) as! Markdown.Image, baseURL: baseURL)
        case let p as Paragraph:
            SwiftUI.Text(MarkdownInline.attributed(p))
                .font(.system(size: 13))
                .lineSpacing(4)
                .padding(.bottom, 8)
                .textSelection(.enabled)
        case let list as UnorderedList:
            ListBlock(items: Array(list.listItems), ordered: false, baseURL: baseURL)
        case let list as OrderedList:
            ListBlock(items: Array(list.listItems), ordered: true, start: Int(list.startIndex), baseURL: baseURL)
        case let quote as BlockQuote:
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(quote.blockChildren.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child, baseURL: baseURL)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        case let code as CodeBlock:
            ScrollView(.horizontal, showsIndicators: false) {
                SwiftUI.Text(code.code.trimmingCharacters(in: .newlines))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(OpsTheme.codeBackground))
            .padding(.bottom, 10)
        case let table as Markdown.Table:
            TableBlock(table: table)
        case is ThematicBreak:
            Rectangle().fill(OpsTheme.separator).frame(height: 1).padding(.vertical, 16)
        case let html as HTMLBlock:
            SwiftUI.Text(html.rawHTML).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).padding(.bottom, 8)
        default:
            if let container = block as? BlockContainer {
                ForEach(Array(container.blockChildren.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(block: child, baseURL: baseURL)
                }
            } else {
                SwiftUI.Text(block.format()).font(.system(size: 13)).padding(.bottom, 8)
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat { [22, 17, 15, 13, 13, 13][max(0, min(level - 1, 5))] }
    private func headingTop(_ level: Int) -> CGFloat { [20, 16, 12, 8, 8, 8][max(0, min(level - 1, 5))] }
}

/// A paragraph that is only an image: http(s) sources load asynchronously, others resolve against the documents folder.
private struct ImageBlock: View {
    let image: Markdown.Image
    var baseURL: URL?

    var body: some View {
        if let source = image.source, let url = URL(string: source) {
            if url.scheme == "http" || url.scheme == "https" {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxWidth: OpsTheme.readerMaxWidth)
                    .padding(.bottom, 10)
            } else if let base = baseURL, let ns = NSImage(contentsOf: base.appendingPathComponent(source)) {
                SwiftUI.Image(nsImage: ns).resizable().scaledToFit()
                    .frame(maxWidth: OpsTheme.readerMaxWidth)
                    .padding(.bottom, 10)
            } else {
                SwiftUI.Text(image.plainText).font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 8)
            }
        }
    }
}

private struct ListBlock: View {
    let items: [ListItem]
    let ordered: Bool
    /// First number of an ordered list ("3." starts at 3, as in the Markdown source).
    var start: Int = 1
    var baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(index: index, checkbox: item.checkbox)
                        .frame(width: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(item.blockChildren.enumerated()), id: \.offset) { _, child in
                            if let p = child as? Paragraph {
                                SwiftUI.Text(MarkdownInline.attributed(p)).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                            } else {
                                MarkdownBlockView(block: child, baseURL: baseURL).padding(.top, 3)
                            }
                        }
                    }
                }
            }
        }
        .padding(.leading, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func marker(index: Int, checkbox: Checkbox?) -> some View {
        if let checkbox {
            SwiftUI.Image(systemName: checkbox == .checked ? "checkmark.square" : "square")
                .font(.system(size: 12, weight: .light)).foregroundStyle(.secondary)
        } else if ordered {
            SwiftUI.Text("\(start + index).").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            SwiftUI.Text("•").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

/// Column-width measurement for reader tables, kept pure (strings in, widths out) so the
/// layout maths can be unit-tested without building a view.
///
/// A SwiftUI `Grid` mis-places rows whose cells have differing heights (a wrapped cell's first
/// line is drawn a line too high, overlapping the row above), so `TableBlock` lays rows out by
/// hand and needs one fixed width per column decided up front.
enum TableLayout {
    /// One measured cell. `isCode` cells are drawn in the monospaced reader font,
    /// which is wider than the system font at the same size, so they must be
    /// measured with it or a column of `code` runs gets clipped.
    struct Cell {
        let text: String
        let isCode: Bool

        init(_ text: String, isCode: Bool = false) {
            self.text = text
            self.isCode = isCode
        }
    }

    static let minColumnWidth: CGFloat = 60
    static let maxColumnWidth: CGFloat = 300
    static let columnSpacing: CGFloat = 16
    static let cellFontSize: CGFloat = 12
    /// Slack added to the measured single-line width so the text never sits flush against the frame.
    static let padding: CGFloat = 4

    /// The width each column should get: the widest single-line cell in that column, plus
    /// `padding`, clamped to `minColumnWidth ... maxColumnWidth`. Cells wider than the clamp wrap.
    static func columnWidths(header: [Cell], rows: [[Cell]]) -> [CGFloat] {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return [] }
        var widest = [CGFloat](repeating: 0, count: columns)
        for (index, cell) in header.enumerated() where index < columns {
            widest[index] = max(widest[index], singleLineWidth(cell, weight: .semibold))
        }
        for row in rows {
            for (index, cell) in row.enumerated() where index < columns {
                widest[index] = max(widest[index], singleLineWidth(cell, weight: .regular))
            }
        }
        return widest.map { min(max($0 + padding, minColumnWidth), maxColumnWidth) }
    }

    /// Plain-text convenience: no cell is code.
    static func columnWidths(header: [String], rows: [[String]]) -> [CGFloat] {
        columnWidths(header: header.map { Cell($0) }, rows: rows.map { $0.map { Cell($0) } })
    }

    /// Total laid-out width of a table with these column widths, gaps included.
    static func totalWidth(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + columnSpacing * CGFloat(widths.count - 1)
    }

    private static func singleLineWidth(_ cell: Cell, weight: NSFont.Weight) -> CGFloat {
        let font = cell.isCode
            ? NSFont.monospacedSystemFont(ofSize: cellFontSize, weight: .regular)
            : NSFont.systemFont(ofSize: cellFontSize, weight: weight)
        return NSAttributedString(string: cell.text, attributes: [.font: font]).size().width
    }
}

private struct TableBlock: View {
    let table: Markdown.Table

    // Explicit rows rather than a `Grid`: with `Grid` a cell that wraps to several lines pushes
    // its own row's baseline up and overlaps the row above (seen on "Other hardware"). Fixed
    // per-column widths computed up front give each `HStack` row a stable height instead, and a
    // table that genuinely cannot fit the reader column still scrolls horizontally.
    var body: some View {
        let header = Array(table.head.cells)
        let rows = table.body.rows.map { Array($0.cells) }
        let widths = TableLayout.columnWidths(header: header.map(Self.measured),
                                              rows: rows.map { $0.map(Self.measured) })
        let total = TableLayout.totalWidth(widths)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(cells: header, widths: widths, weight: .semibold, verticalPadding: 6)
                Rectangle().fill(OpsTheme.separator).frame(width: total, height: 1)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    row(cells: cells, widths: widths, weight: .regular, verticalPadding: 5)
                    Rectangle().fill(OpsTheme.separator.opacity(0.6)).frame(width: total, height: 1)
                }
            }
        }
        .padding(.bottom, 12)
    }

    /// A cell whose every inline child is `InlineCode` renders monospaced, so it
    /// has to be measured that way (see `TableLayout.Cell`).
    private static func measured(_ cell: Markdown.Table.Cell) -> TableLayout.Cell {
        let children = Array(cell.children)
        let isCode = !children.isEmpty && children.allSatisfy { $0 is InlineCode }
        return TableLayout.Cell(cell.plainText, isCode: isCode)
    }

    private func row(cells: [Markdown.Table.Cell], widths: [CGFloat],
                     weight: Font.Weight, verticalPadding: CGFloat) -> some View {
        HStack(alignment: .top, spacing: TableLayout.columnSpacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                SwiftUI.Text(MarkdownInline.attributed(cell))
                    .font(.system(size: TableLayout.cellFontSize, weight: weight))
                    .frame(width: index < widths.count ? widths[index] : TableLayout.minColumnWidth,
                           alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, verticalPadding)
    }
}
