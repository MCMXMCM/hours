@testable import Hours
import XCTest
import SwiftUI

final class OfficeReaderScrollRestorationTests: XCTestCase {
    func testScrollGeometryAccountsForNavigationAndBottomInsets() {
        let geometry = OfficeReaderScrollGeometry(ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: 684),
            contentSize: CGSize(width: 402, height: 10_000),
            contentInsets: EdgeInsets(top: 116, leading: 0, bottom: 34, trailing: 0),
            containerSize: CGSize(width: 402, height: 874)
        ))
        XCTAssertEqual(geometry.offset, 800)
        XCTAssertEqual(geometry.maximumOffset, 9_276)
    }

    func testRestoredOffsetIsClampedToCurrentScrollableRange() {
        XCTAssertEqual(
            OfficeReaderScrollRestoration.offset(
                12_000,
                maximumOffset: 8_000
            ),
            8_000
        )
        XCTAssertEqual(
            OfficeReaderScrollRestoration.offset(
                -100,
                maximumOffset: 8_000
            ),
            0
        )
    }

    func testInvalidRestorationGeometryFallsBackToTop() {
        XCTAssertEqual(
            OfficeReaderScrollRestoration.offset(
                .nan,
                maximumOffset: 8_000
            ),
            0
        )
        XCTAssertEqual(
            OfficeReaderScrollRestoration.offset(
                2_000,
                maximumOffset: .infinity
            ),
            0
        )
    }

    func testAnchorKeepsExactPositionWithinVisibleSection() {
        let anchor = OfficeReaderScrollRestoration.anchor(in: [
            "previous": CGRect(x: 0, y: -900, width: 400, height: 700),
            "prayer": CGRect(x: 0, y: -200, width: 400, height: 800),
            "next": CGRect(x: 0, y: 600, width: 400, height: 400)
        ])
        XCTAssertEqual(anchor, OfficeReaderScrollAnchor(sectionID: "prayer", viewportY: -200))
    }

    func testAnchorPreservesGapAboveFirstVisibleSection() {
        XCTAssertEqual(
            OfficeReaderScrollRestoration.anchor(in: [
                "prayer": CGRect(x: 0, y: 40, width: 400, height: 800)
            ]),
            OfficeReaderScrollAnchor(sectionID: "prayer", viewportY: 40)
        )
        XCTAssertNil(OfficeReaderScrollRestoration.anchor(in: [:]))
    }
}
