import SwiftUI

/// Key/value rows. Rows are tracked by a local UUID so duplicate or empty keys do not collide.
struct PropertiesEditor: View {
    @Binding var properties: [DocProperty]
    @State private var rows: [Row] = []

    private struct Row: Identifiable { let id = UUID(); var key: String; var value: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    TextField("key", text: $row.key).frame(width: 140)
                    TextField("value", text: $row.value)
                    Button { rows.removeAll { $0.id == row.id }; sync() } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .onChange(of: row.key) { sync() }
                .onChange(of: row.value) { sync() }
            }
            Button { rows.append(Row(key: "", value: "")) } label: {
                Label("Add Property", systemImage: "plus").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { rows = properties.map { Row(key: $0.key, value: $0.value) } }
        .onChange(of: properties) { _, newValue in
            // Only resync when the change came from outside this view (e.g. Load Markdown
            // File replacing the whole draft) — sync() below already keeps rows and
            // properties equivalent, so this guard avoids rebuilding rows (and losing
            // in-progress text field focus) on every keystroke.
            let currentPairs = rows.map { DocProperty(key: $0.key, value: $0.value) }
            if currentPairs != newValue {
                rows = newValue.map { Row(key: $0.key, value: $0.value) }
            }
        }
    }

    private func sync() {
        properties = rows.map { DocProperty(key: $0.key, value: $0.value) }
    }
}
