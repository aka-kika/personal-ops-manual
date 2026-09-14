import SwiftUI

/// Every column starts with the same two rows so titles line up across the window:
/// a 38 pt chrome row merged with the title bar (buttons live here) and a 32 pt title row.
struct ColumnHeader<Chrome: View, Title: View>: View {
    var leadingInset: CGFloat = 0
    @ViewBuilder var chrome: () -> Chrome
    @ViewBuilder var title: () -> Title

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                chrome()
            }
            .frame(maxWidth: .infinity)
            .frame(height: OpsChrome.columnHeaderHeight)
            .padding(.leading, OpsChrome.columnHeaderHorizontalPadding + leadingInset)
            .padding(.trailing, OpsChrome.columnHeaderHorizontalPadding - 6)

            title()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: OpsChrome.titleRowHeight)
                .padding(.horizontal, OpsChrome.columnHeaderHorizontalPadding)
        }
    }
}
