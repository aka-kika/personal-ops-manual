import XCTest
import AppKit
@testable import OpsManual

@MainActor
final class TitlebarOverlayTests: XCTestCase {
    func testOpenOverlayTakesTheHeaderStripAndClosesOnClick() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        OpsWindowChrome.installTitlebarClickRouter(in: window)
        let router = try XCTUnwrap(window.titlebarAccessoryViewControllers.compactMap { $0.view as? TitlebarClickRouterView }.first)
        let guardView = TitlebarOverlayGuardView()
        window.contentView?.addSubview(guardView)

        let inside = NSPoint(x: router.frame.midX, y: router.frame.midY)
        XCTAssertNil(router.hitTest(inside), "with no anchors and no overlay, clicks pass to the title bar")

        var dismissed = 0
        guardView.dismiss = { dismissed += 1 }
        XCTAssertTrue(router.hitTest(inside) === router)
        XCTAssertFalse(router.mouseDownCanMoveWindow)
        router.mouseUp(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)))
        XCTAssertEqual(dismissed, 1)

        guardView.dismiss = nil
        XCTAssertNil(router.hitTest(inside))
        XCTAssertTrue(router.mouseDownCanMoveWindow)
    }
}
