import Foundation

/// What the editor sheet edits. Never carries id or dates; the store assigns those.
struct DocDraft: Hashable, Sendable {
    var title = ""
    var category = ""
    var summary = ""
    var body = ""
    var tags: [String] = []
    var properties: [DocProperty] = []

    init() {}

    init(document: OpsDocument) {
        title = document.title
        category = document.category
        summary = document.summary
        body = document.body
        tags = document.tags
        properties = document.properties
    }
}
