import XCTest

@MainActor
final class CantorGuideScrollingUITests: XCTestCase {
    func testCantorGuideKeepsSalveReginaPlaybackVisible() {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-reader-section",
            "compline-ordered-42",
            "--ui-test-cantor-follow",
        ]
        app.launch()

        openOffice("compline", in: app)

        let firstSalveReginaNeume = app.buttons[
            "reference-cccbdc9d2a0c189f-note-0"
        ]
        XCTAssertTrue(
            firstSalveReginaNeume.waitForExistence(timeout: 10)
                && firstSalveReginaNeume.isHittable,
            "The first neume of today's Salve Regina should be reachable."
        )
        let dragStart = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
        )
        let dragEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38)
        )
        for _ in 0..<4
        where firstSalveReginaNeume.isHittable
            && firstSalveReginaNeume.frame.midY > app.frame.midY * 0.72 {
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }
        XCTAssertTrue(firstSalveReginaNeume.isHittable)
        XCTAssertLessThan(firstSalveReginaNeume.frame.midY, app.frame.midY)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        firstSalveReginaNeume.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(10))
        XCTAssertTrue(
            app.otherElements["cantor-tracking-passed"]
                .waitForExistence(timeout: 10),
            "Opening should preserve the selected Salve note, and playback should "
                + "auto-follow the advanced active note above the guide."
        )
    }

    private func openOffice(
        _ hour: String,
        in app: XCUIApplication
    ) {
        let selectedHour = app.buttons["hour-\(hour)"]
        if !selectedHour.waitForExistence(timeout: 1) {
            let option = app.buttons["hour-option-\(hour)"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let selected = NSPredicate(
                format: "label == %@",
                "Pray \(hour.capitalized)"
            )
            let prayButton = app.buttons["pray-selected-hour"]
            expectation(for: selected, evaluatedWith: prayButton)
            waitForExpectations(timeout: 3)
        }

        let prayButton = app.buttons["pray-selected-hour"]
        XCTAssertTrue(prayButton.waitForExistence(timeout: 3))
        prayButton.tap()
    }
}
