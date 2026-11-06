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

    /// Drift's two pastels (the third color is the accent): peach = drifted, sage = holds.
    static let peach = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.941, green: 0.765, blue: 0.675, alpha: 1)   // #F0C3AC
            : NSColor(srgbRed: 0.604, green: 0.353, blue: 0.235, alpha: 1)   // #9A5A3C, readable on light
    })
    static let peachFill = Color(.sRGB, red: 0.922, green: 0.710, blue: 0.604).opacity(0.26)   // #EBB59A
    static let peachMark = Color(.sRGB, red: 0.922, green: 0.710, blue: 0.604)
    static let sage = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.710, green: 0.863, blue: 0.765, alpha: 1)   // #B5DCC3
            : NSColor(srgbRed: 0.243, green: 0.478, blue: 0.333, alpha: 1)   // #3E7A55
    })
    static let sageFill = Color(.sRGB, red: 0.624, green: 0.812, blue: 0.690).opacity(0.24)   // #9FCFB0
    static let sageMark = Color(.sRGB, red: 0.624, green: 0.812, blue: 0.690)
    static let cardStroke = separator
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
