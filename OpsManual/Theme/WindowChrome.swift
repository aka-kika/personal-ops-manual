import AppKit
import SwiftUI

enum OpsChrome {
    /// Header row doubles as the title bar (reshelf-style).
    static let columnHeaderHeight: CGFloat = 38
    static let titleRowHeight: CGFloat = 32
    static let columnHeaderHorizontalPadding: CGFloat = 16
    /// Clear traffic lights on the leftmost column.
    static let trafficLightHeaderInset: CGFloat = 64
    static let chromeIconSize: CGFloat = 13
    static let chromeButtonSize: CGFloat = 24
}

/// Quiet header icon button (reshelf sizing). Clicks under a merged title bar
/// need the reshelf click router — see Docs/HANDOFF_TITLEBAR_CLICKS.md (Fable).
struct HeaderChromeButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: OpsChrome.chromeIconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: OpsChrome.chromeButtonSize, height: OpsChrome.chromeButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help.isEmpty ? systemImage : help)
        .titlebarClickable(action: action)
    }
}

/// Applies reshelf-style transparent title bar and continuously hides the system
/// glass strip that otherwise sits on top of column headers.
struct MainWindowChromeConfigurator: NSViewRepresentable {
    final class ChromeView: NSView {
        nonisolated(unsafe) private var windowTokens: [NSObjectProtocol] = []

        deinit {
            windowTokens.forEach(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowTokens.forEach(NotificationCenter.default.removeObserver)
            windowTokens = []
            guard let window else { return }

            Task { @MainActor in
                OpsWindowChrome.apply(to: window)
            }

            // AppKit recreates title-bar glass lazily — re-hide on every draw.
            // SwiftUI toolbar rebuilds can also drop the click-router accessory,
            // so re-assert it here too (cheap contains check inside).
            // `window.toolbar = nil` goes here rather than `.toolbar(.hidden,
            // for: .windowToolbar)` on the view: that modifier hides the whole
            // NSTitlebarContainerView, taking the traffic lights and the click
            // router with it. Clearing the toolbar object leaves the title bar.
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                Task { @MainActor in
                    if window.toolbar != nil { window.toolbar = nil }
                    OpsWindowChrome.hideTitlebarBackdrops(in: window)
                    OpsWindowChrome.installTitlebarClickRouter(in: window)
                }
            }
            windowTokens.append(token)

            DispatchQueue.main.async {
                Task { @MainActor in
                    OpsWindowChrome.apply(to: window)
                }
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        ChromeView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Deployment target is macOS 26.0, so the API is always available here —
    /// no `#available` guard needed (the file this was adapted from targets an earlier minimum).
    func hidesTopScrollEdgeEffect() -> some View {
        scrollEdgeEffectHidden(true, for: .top)
    }

    /// Column lays out from the window top edge (under traffic lights).
    func titleBarColumn() -> some View {
        ignoresSafeArea(.container, edges: .top)
            .hidesTopScrollEdgeEffect()
    }
}

