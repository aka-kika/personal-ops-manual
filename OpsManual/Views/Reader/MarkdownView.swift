import SwiftUI
import Markdown

struct MarkdownView: View {
    let markdown: String
    var baseURL: URL?

    var body: some View {
        let doc = Markdown.Document(parsing: markdown)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(doc.blockChildren.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, baseURL: baseURL)
            }
        }
        .frame(maxWidth: OpsTheme.readerMaxWidth, alignment: .leading)
    }
}
