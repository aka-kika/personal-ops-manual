import AppKit
import SwiftUI

// Port of reshelf's title-bar click router: system title-bar claims mouse
// events as window-drags, so header controls need anchors + a transparent
// accessory that forwards clicks to button actions / AppKit menus.

// MARK: - Anchor registry

final class TitlebarClickAnchorRegistry: @unchecked Sendable {
    static let shared = TitlebarClickAnchorRegistry()
    private let anchors = NSHashTable<TitlebarClickAnchorView>.weakObjects()
    private let lock = NSLock()

    func register(_ anchor: TitlebarClickAnchorView) {
        lock.lock()
        defer { lock.unlock() }
        anchors.add(anchor)
    }

    // All call sites run on the main thread (NSView overrides, a
    // RunLoop.main timer, or a MainActor Task) even though the surrounding
    // registry is merely Sendable; annotate so the isolated NSView reads
    // below type-check without a broader unsafe escape hatch.
    @MainActor
    func liveAnchors(in window: NSWindow) -> [TitlebarClickAnchorView] {
        lock.lock()
        defer { lock.unlock() }
        return anchors.allObjects.filter { anchor in
            anchor.window === window && anchor.superview != nil
                && !anchor.convert(anchor.bounds, to: nil).isEmpty
        }
    }
}

final class TitlebarClickAnchorView: NSView {
    /// Plain buttons: fire on mouse-up. nil → menu: performClick on AppKit popup.
    var clickAction: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            TitlebarClickAnchorRegistry.shared.register(self)
        }
    }
}

private struct TitlebarClickAnchor: NSViewRepresentable {
    var action: (() -> Void)?

    func makeNSView(context: Context) -> TitlebarClickAnchorView {
        let view = TitlebarClickAnchorView()
        view.clickAction = action
        return view
    }

    func updateNSView(_ nsView: TitlebarClickAnchorView, context: Context) {
        nsView.clickAction = action
    }
}

extension View {
    /// Mark an interactive control in the merged title-bar/header row.
    /// Pass `action` for plain buttons; omit for menus.
    func titlebarClickable(action: (() -> Void)? = nil) -> some View {
        overlay(TitlebarClickAnchor(action: action).allowsHitTesting(false))
    }
}

// MARK: - Router accessory

enum OpsWindowChrome {
    /// Soft gray dark canvas — never pure black.
    private static let softDarkBackground = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.176, alpha: 1)

    /// KVO guards so AppKit can't re-show title-bar glass. Main-actor only.
    /// Values carry a weak ref to the observed view so entries for dead views
    /// can be pruned (audit 6.3: unbounded growth over long sessions).
    @MainActor private static var backdropGuards: [ObjectIdentifier: (view: WeakViewBox, observation: NSKeyValueObservation)] = [:]

    final class WeakViewBox {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    @MainActor
    static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? softDarkBackground
                : NSColor.windowBackgroundColor
        }
        flattenChromeMaterials(in: window)
        hideTitlebarBackdrops(in: window)
        installTitlebarClickRouter(in: window)
    }

    @MainActor
    static func installTitlebarClickRouter(in window: NSWindow) {
        let installed = window.titlebarAccessoryViewControllers.contains {
            $0.view is TitlebarClickRouterView
        }
        guard !installed else { return }
        let controller = NSTitlebarAccessoryViewController()
        // Full-width strip under the traffic-light band. `.right` only covered
        // the trailing title-bar, so the leading sidebar toggle (when the
        // sidebar is hidden and sits under the title bar) never got a hole
        // and clicks died as window-drags.
        let height = max(OpsChrome.columnHeaderHeight, 38)
        let router = TitlebarClickRouterView(
            frame: NSRect(x: 0, y: 0, width: max(window.frame.width, 800), height: height)
        )
        router.autoresizingMask = [.width]
        controller.view = router
        controller.layoutAttribute = .top
        controller.fullScreenMinHeight = 0
        window.addTitlebarAccessoryViewController(controller)
    }

    @MainActor
    private static func flattenChromeMaterials(in window: NSWindow) {
        let targets: Set<NSVisualEffectView.Material> = [.sidebar, .titlebar, .headerView]
        let roots = [window.contentView, window.contentView?.superview].compactMap { $0 }
        for root in roots {
            for effectView in root.descendantVisualEffectViews()
            where targets.contains(effectView.material) {
                effectView.material = .windowBackground
                effectView.blendingMode = .withinWindow
                effectView.state = .followsWindowActiveState
            }
        }
    }

    /// Last full-tree sweep per window — the sweep walks EVERY NSView and
    /// string-formats class names, and NSWindow.didUpdate fires on nearly
    /// every event-loop pass. Unthrottled, this burned CPU on each keystroke
    /// with a large grid (audit 6.2). The KVO pins keep already-hidden glass
    /// hidden between sweeps, so a 0.5s cadence loses nothing visible.
    @MainActor private static var lastBackdropSweep: [ObjectIdentifier: TimeInterval] = [:]

    /// Hide macOS 26/27 glass / scroll-pocket layers that paint over headers.
    @MainActor
    static func hideTitlebarBackdrops(in window: NSWindow) {
        let key = ObjectIdentifier(window)
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastBackdropSweep[key], now - last < 0.5 { return }
        lastBackdropSweep[key] = now
        guard let contentView = window.contentView else { return }

        for splitView in contentView.descendantSplitViews() {
            for view in splitView.subviews
            where String(describing: type(of: view)).contains("NSTitlebarBackgroundView") {
                hideAndPin(view)
            }
        }

        for scrollView in contentView.descendantScrollViews() {
            for view in scrollView.subviews {
                let name = String(describing: type(of: view))
                guard name == "NSScrollPocket" || name == "BackdropView" else { continue }
                hideAndPin(view)
            }
        }

        if let frameView = contentView.superview {
            for view in frameView.allDescendants() {
                let name = String(describing: type(of: view))
                if name.contains("NSTitlebarBackgroundView")
                    || name == "NSScrollPocket"
                    || name.contains("TitlebarDecoration") {
                    hideAndPin(view)
                }
            }
        }
    }

    @MainActor
    private static func hideAndPin(_ view: NSView) {
        view.isHidden = true
        let key = ObjectIdentifier(view)
        // Recycled addresses can collide with a dead view's key — always
        // replace so the NEW view gets pinned (audit #10).
        if let stale = backdropGuards.removeValue(forKey: key) {
            stale.observation.invalidate()
        }
        backdropGuards[key] = (
            WeakViewBox(view),
            view.observe(\.isHidden, options: [.new]) { view, _ in
                DispatchQueue.main.async {
                    if !view.isHidden { view.isHidden = true }
                }
            }
        )
        // Prune entries whose views AppKit already discarded.
        for (staleKey, entry) in backdropGuards where entry.view.view == nil {
            entry.observation.invalidate()
            backdropGuards.removeValue(forKey: staleKey)
        }
    }
}

private extension NSView {
    func descendantSplitViews() -> [NSSplitView] {
        var result: [NSSplitView] = []
        for subview in subviews {
            if let splitView = subview as? NSSplitView { result.append(splitView) }
            result.append(contentsOf: subview.descendantSplitViews())
        }
        return result
    }

    func descendantScrollViews() -> [NSScrollView] {
        var result: [NSScrollView] = []
        for subview in subviews {
            if let scrollView = subview as? NSScrollView { result.append(scrollView) }
            result.append(contentsOf: subview.descendantScrollViews())
        }
        return result
    }

    func descendantVisualEffectViews() -> [NSVisualEffectView] {
        var result: [NSVisualEffectView] = []
        for subview in subviews {
            if let effectView = subview as? NSVisualEffectView { result.append(effectView) }
            result.append(contentsOf: subview.descendantVisualEffectViews())
        }
        return result
    }

    func allDescendants() -> [NSView] {
        var result: [NSView] = []
        for subview in subviews {
            result.append(subview)
            result.append(contentsOf: subview.allDescendants())
        }
        return result
    }
}

final class TitlebarClickRouterView: NSView {
    private var holes: [TitlebarClickHoleView] = []
    private var blockingViews: [NSView] = []
    private static let blockingViewClass: NSView.Type? =
        NSClassFromString("NSTitlebarContainerBlockingView") as? NSView.Type
    nonisolated(unsafe) private var syncTimer: Timer?

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncTimer?.invalidate()
        syncTimer = nil
        blockingViews.forEach { $0.removeFromSuperview() }
        blockingViews.removeAll()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            // Scheduled on RunLoop.main below, so this always fires on the
            // main thread even though Timer's closure type is nonisolated.
            MainActor.assumeIsolated {
                self?.syncHoles(syncBlockingViews: true)
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
        syncHoles(syncBlockingViews: true)
    }

    override func layout() {
        super.layout()
        syncHoles(syncBlockingViews: true)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        syncHoles(syncBlockingViews: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncHoles(syncBlockingViews: false)
    }

    deinit {
        // Invalidate on main — the timer was scheduled there and invalidate
        // is thread-affine (audit 6.14).
        let timer = syncTimer
        DispatchQueue.main.async { timer?.invalidate() }
    }

    private var titlebarContainer: NSView? {
        var view: NSView? = superview
        while let v = view {
            if String(describing: type(of: v)).contains("NSTitlebarContainerView") {
                return v
            }
            view = v.superview
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, window != nil else { return nil }
        syncHoles(syncBlockingViews: false)
        let windowPoint = superview.convert(point, to: nil)
        let localPoint = convert(windowPoint, from: nil)
        return holes.first { !$0.frame.isEmpty && $0.frame.contains(localPoint) }
    }

    private func syncHoles(syncBlockingViews: Bool) {
        guard let window else { return }
        let anchors = TitlebarClickAnchorRegistry.shared.liveAnchors(in: window)
        let frames = anchors.map { $0.convert($0.bounds, to: nil) }
        while holes.count < anchors.count {
            let hole = TitlebarClickHoleView()
            addSubview(hole)
            holes.append(hole)
        }
        while holes.count > anchors.count {
            holes.removeLast().removeFromSuperview()
        }
        for (hole, (anchor, frame)) in zip(holes, zip(anchors, frames)) {
            hole.anchor = anchor
            // Map window-space control frames into this view. Prefer full
            // local rects even when slightly outside bounds so leading
            // chrome (sidebar.left under traffic lights) still receives holes.
            var local = convert(frame, from: nil)
            if local.isNull || local.isEmpty {
                local = .zero
            } else {
                // Expand a few points so hit targets match the painted button.
                local = local.insetBy(dx: -2, dy: -2)
            }
            if hole.frame != local {
                hole.frame = local
            }
        }
        if syncBlockingViews {
            syncDragRegionBlockers(controlFrames: frames)
        }
    }

    private func syncDragRegionBlockers(controlFrames: [NSRect]) {
        guard let blockingClass = Self.blockingViewClass,
              let container = titlebarContainer else { return }
        while blockingViews.count < controlFrames.count {
            let blocker = blockingClass.init(frame: .zero)
            container.addSubview(blocker, positioned: .below, relativeTo: nil)
            blockingViews.append(blocker)
        }
        while blockingViews.count > controlFrames.count {
            blockingViews.removeLast().removeFromSuperview()
        }
        for (blocker, frame) in zip(blockingViews, controlFrames) {
            if blocker.superview !== container {
                container.addSubview(blocker, positioned: .below, relativeTo: nil)
            }
            let local = container.convert(frame, from: nil)
            if blocker.frame != local {
                blocker.frame = local
            }
        }
    }
}

final class TitlebarClickHoleView: NSButton {
    weak var anchor: TitlebarClickAnchorView?
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        isTransparent = true
        refusesFirstResponder = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        if anchor?.clickAction != nil {
            isPressed = true
            return
        }
        underlyingControl(at: event.locationInWindow)?.performClick(nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer { isPressed = false }
        guard isPressed, let action = anchor?.clickAction else { return }
        let local = convert(event.locationInWindow, from: nil)
        if bounds.insetBy(dx: -4, dy: -4).contains(local) {
            action()
        }
    }

    private func underlyingControl(at locationInWindow: NSPoint) -> NSControl? {
        guard let window, let contentView = window.contentView else { return nil }
        let root = contentView.superview ?? contentView
        var view = contentView.hitTest(root.convert(locationInWindow, from: nil))
        while let current = view {
            if let control = current as? NSControl {
                return control
            }
            view = current.superview
        }
        return nil
    }
}
