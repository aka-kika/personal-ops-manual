import SwiftUI
import AppKit

enum OpsTheme {
    /// Soft dark #2A2A2D in dark mode; system window background in light.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.165, green: 0.165, blue: 0.176, alpha: 1)
            : NSColor.windowBackgroundColor
    })

    /// Sidebar column: #2E3036 in dark so it reads as its own surface next
    /// to the canvas; a shade darker than the window in light.
    static let sidebarCanvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.180, green: 0.188, blue: 0.212, alpha: 1)
            : NSColor(srgbRed: 0.957, green: 0.957, blue: 0.965, alpha: 1)
    })

    static let separator = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)
    })

    static let selection = Color.accentColor.opacity(0.12)
    static let codeBackground = Color.primary.opacity(0.06)

    static let titleFont = Font.system(size: 15, weight: .medium)
    static let subtitleFont = Font.system(size: 12)
    static let rowTitleFont = Font.system(size: 13, weight: .medium)
    static let rowFont = Font.system(size: 13)
    static let excerptFont = Font.system(size: 12)
    static let metaFont = Font.system(size: 11)
    static let sectionLabelFont = Font.system(size: 11, weight: .medium)
    static let sidebarIcon = Font.system(size: 13, weight: .light)

    static let readerMaxWidth: CGFloat = 760
}
