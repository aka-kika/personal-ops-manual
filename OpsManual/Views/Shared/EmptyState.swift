import SwiftUI

struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text)
            .font(OpsTheme.rowFont)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
