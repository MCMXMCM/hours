@testable import Hours
import UIKit
import XCTest

@MainActor
final class OfficeReaderScrollTrackingTests: XCTestCase {
    private enum TeardownContext {
        @TaskLocal static var active = false
    }

    func testReaderMarkersDeallocateInsideTaskLocalContext() {
        TeardownContext.$active.withValue(true) {
            let state = OfficeReaderTransientState()
            for _ in 0..<100 {
                weak var released: UIView?
                autoreleasepool {
                    let marker = OfficeReaderScrollViewAccessor.ResolverView()
                    released = marker
                    state.registerSectionView(marker, for: "psalm")
                }
                XCTAssertNil(released)
                XCTAssertTrue(state.sectionViews.isEmpty)
            }
        }
    }

    func testReusedLayoutMarkerCannotIdentifyTwoDifferentSections() {
        let state = OfficeReaderTransientState()
        let reused = UIView()
        let other = UIView()
        state.registerSectionView(reused, for: "psalm")
        state.registerSectionView(other, for: "hymn")
        state.registerSectionView(reused, for: "canticle")
        XCTAssertNil(state.sectionViews["psalm"])
        XCTAssertTrue(state.sectionViews["canticle"] === reused)
        XCTAssertTrue(state.sectionViews["hymn"] === other)
    }

    func testLateNativeResetPreservesPassageUntilProtectionIsReleased() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 116
        scrollView.contentSize = CGSize(width: 402, height: 10_000)
        controller.view.addSubview(scrollView)
        let section = UIView(frame: CGRect(x: 0, y: 600, width: 402, height: 800))
        scrollView.addSubview(section)
        scrollView.contentOffset.y = 700

        let state = OfficeReaderTransientState()
        state.scrollView = scrollView
        state.registerSectionView(section, for: "prayer")
        state.protectedAnchor = OfficeReaderScrollRestoration.anchor(in: state.sectionFrames)
        XCTAssertEqual(state.protectedAnchor?.viewportY, -216)

        // Reproduce the native reset that SwiftUI's geometry callback misses.
        scrollView.contentOffset.y = -116
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in abs(scrollView.contentOffset.y - 700) < 1 },
            object: nil
        )
        await fulfillment(of: [restored], timeout: 2)

        // Explicit navigation must regain full control of the scroll view.
        state.protectedAnchor = nil
        scrollView.contentOffset.y = 1_500
        await Task.yield()
        XCTAssertEqual(scrollView.contentOffset.y, 1_500)
    }
}
