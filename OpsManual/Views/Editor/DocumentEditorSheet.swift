import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DocumentEditorSheet: View {
    let target: EditorTarget
    @Bindable var store: DocumentStore
    /// Receives the id of a freshly created document; nil for edit and cancel.
    var onDone: (String?) -> Void

    @State private var draft = DocDraft()
    @State private var tagsText = ""
    @State private var newCategoryMode = false
    @State private var errorText: String?

    private var isEditing: Bool { if case .edit = target { return true } else { return false } }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Document" : "New Document")
                .font(OpsTheme.titleFont)
                .padding(.bottom, 14)

            Form {
                TextField("Title", text: $draft.title)
                categoryField
                TextField("Summary", text: $draft.summary)
                TextField("Tags", text: $tagsText, prompt: Text("comma, separated"))
                LabeledContent("Properties") { PropertiesEditor(properties: $draft.properties) }
                LabeledContent("Body") {
                    TextEditor(text: $draft.body)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 240)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(OpsTheme.separator))
                }
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)

            if let errorText {
                Text(errorText).font(OpsTheme.metaFont).foregroundStyle(.red).padding(.top, 8)
            }

            HStack {
                Button("Load Markdown File…", action: loadFile)
                Spacer()
                Button("Cancel", role: .cancel) { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Create", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 640, height: 620)
        .onAppear(perform: prefill)
    }

    @ViewBuilder
    private var categoryField: some View {
        if newCategoryMode || store.categories.isEmpty {
            HStack {
                TextField("Category", text: $draft.category, prompt: Text("New category name"))
                if !store.categories.isEmpty {
                    Button("Choose Existing") { newCategoryMode = false }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        } else {
            Picker("Category", selection: $draft.category) {
                Text("Choose…").tag("")
                ForEach(store.categories, id: \.name) { Text($0.name).tag($0.name) }
                Divider()
                Text("New Category…").tag("__new__")
            }
            .onChange(of: draft.category) { _, value in
                if value == "__new__" { draft.category = ""; newCategoryMode = true }
            }
        }
    }

    private func prefill() {
        switch target {
        case .new(let category):
            draft = DocDraft()
            draft.category = category
            newCategoryMode = !category.isEmpty && !store.categories.contains { $0.name == category }
        case .edit(let id):
            guard let doc = store.document(id: id) else { return }
            draft = DocDraft(document: doc)
            newCategoryMode = !store.categories.contains { $0.name == doc.category }
        }
        tagsText = draft.tags.joined(separator: ", ")
    }

    private func loadFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"), .plainText]
            .compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        let loaded = MarkdownText.draft(fromMarkdown: raw, fileName: url.lastPathComponent)
        draft.title = loaded.title
        if !loaded.category.isEmpty { draft.category = loaded.category }
        draft.summary = loaded.summary
        draft.tags = loaded.tags
        draft.properties = loaded.properties
        draft.body = loaded.body
        tagsText = loaded.tags.joined(separator: ", ")
        newCategoryMode = !draft.category.isEmpty && !store.categories.contains { $0.name == draft.category }
    }

    private func save() {
        draft.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft.properties = draft.properties.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            switch target {
            case .new:
                let doc = try store.create(draft)
                onDone(doc.id)
            case .edit(let id):
                _ = try store.update(id: id, draft: draft)
                onDone(nil)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
