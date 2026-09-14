import SwiftUI
import Markdown

/// Builds one AttributedString per paragraph so SwiftUI renders it as a single Text.
enum MarkdownInline {
    static func attributed(_ container: some InlineContainer) -> AttributedString {
        attributed(children: container.children)
    }

    static func attributed(children: MarkupChildren) -> AttributedString {
        var out = AttributedString()
        for child in children { out.append(render(child)) }
        return out
    }

    private static func render(_ node: Markup) -> AttributedString {
        switch node {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case is SoftBreak:
            return AttributedString(" ")
        case is LineBreak:
            return AttributedString("\n")
        case let code as InlineCode:
            var a = AttributedString(code.code)
            a.inlinePresentationIntent = .code
            a.font = .system(size: 12, design: .monospaced)
            a.backgroundColor = OpsTheme.codeBackground
            return a
        case let strong as Strong:
            var a = attributed(children: strong.children)
            addIntent(.stronglyEmphasized, to: &a)
            return a
        case let em as Emphasis:
            var a = attributed(children: em.children)
            addIntent(.emphasized, to: &a)
            return a
        case let strike as Strikethrough:
            var a = attributed(children: strike.children)
            a.strikethroughStyle = .single
            return a
        case let link as Markdown.Link:
            // Ruling (overrides swift-markdown's default accent-link behavior): both document
            // links (opsmanual://) and web links render in the normal text colour with a thin
            // underline in a secondary tone -- no accent foreground, no dotted/solid
            // distinction between the two kinds of link.
            //
            // `Text(AttributedString)` tints any run carrying `.link` with the system accent
            // colour unless that run also carries an explicit `foregroundColor`, so the colour
            // has to be set here; assigning it on the whole string applies it to every run.
            //
            // There is no `underlineColor` key on AttributedString in this SDK (only
            // `foregroundColor` and `underlineStyle: Text.LineStyle`); `Text.LineStyle` itself
            // carries an optional `color`, so the underline colour is set there instead of via
            // a separate attribute.
            var a = attributed(children: link.children)
            if let dest = link.destination, let url = URL(string: dest) {
                a.link = url
                a.foregroundColor = Color.primary
                a.underlineStyle = SwiftUI.Text.LineStyle(pattern: .solid, color: Color.secondary.opacity(0.6))
            }
            return a
        case let image as Markdown.Image:
            return AttributedString(image.plainText)
        case let html as InlineHTML:
            return AttributedString(html.rawHTML)
        default:
            if let container = node as? InlineContainer { return attributed(children: container.children) }
            return AttributedString(node.format())
        }
    }

    /// Adds `new` to every run's `inlinePresentationIntent` individually (rather than the
    /// whole-string accessor, which returns nil -- and would overwrite every run -- as soon as
    /// runs differ, e.g. plain text next to nested emphasis or inline code inside a strong run).
    private static func addIntent(_ new: InlinePresentationIntent, to a: inout AttributedString) {
        for run in a.runs {
            let existing = run.inlinePresentationIntent ?? []
            a[run.range].inlinePresentationIntent = existing.union(new)
        }
    }
}
