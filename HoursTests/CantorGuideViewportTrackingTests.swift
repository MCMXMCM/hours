@testable import Hours
import XCTest

@MainActor
final class CantorGuideViewportTrackingTests: XCTestCase {
    func testOnlyTappedSectionOwnsHighlightForRepeatedScore() {
        let selectedSectionID = "matins-invitatory-opening"

        XCTAssertTrue(
            CantorGuideHighlightScope.isActive(
                sectionID: selectedSectionID,
                selectedSectionID: selectedSectionID
            )
        )
        XCTAssertFalse(
            CantorGuideHighlightScope.isActive(
                sectionID: "matins-invitatory-repetition",
                selectedSectionID: selectedSectionID
            )
        )
    }

    func testNoSectionOwnsHighlightAfterCantorGuideCloses() {
        XCTAssertFalse(
            CantorGuideHighlightScope.isActive(
                sectionID: "matins-invitatory-opening",
                selectedSectionID: nil
            )
        )
    }

    func testVisibleNeumeDoesNotMoveWhenCantorGuideOpens() {
        let anchor = CantorGuideViewportTracking.scrollAnchorY(
            activeFrame: CGRect(x: 20, y: 105, width: 44, height: 52),
            readerFrame: CGRect(x: 0, y: 100, width: 390, height: 700),
            obscuredBottomHeight: 284
        )

        XCTAssertNil(anchor)
    }

    func testNeumeCoveredByCantorGuideScrollsToVisibleCenter() {
        let anchor = CantorGuideViewportTracking.scrollAnchorY(
            activeFrame: CGRect(x: 20, y: 560, width: 44, height: 52),
            readerFrame: CGRect(x: 0, y: 100, width: 390, height: 700),
            obscuredBottomHeight: 284
        )

        XCTAssertEqual(
            try XCTUnwrap(anchor),
            0.28,
            accuracy: 0.000_001
        )
    }

    func testLoopedNeumeAboveViewportScrollsBackIntoView() {
        let anchor = CantorGuideViewportTracking.scrollAnchorY(
            activeFrame: CGRect(x: 20, y: 60, width: 44, height: 52),
            readerFrame: CGRect(x: 0, y: 100, width: 390, height: 700),
            obscuredBottomHeight: 284
        )

        XCTAssertNotNil(anchor)
    }
}
