import XCTest

@MainActor
final class ReaderRestorationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        MainActor.assumeIsolated { UITestAppState.reset() }
    }

    func testRoman1960ReaderSurvivesBackgroundAndRelaunch() throws {
        try checkRestoration(tradition: "roman1960")
    }

    func testRoman1954ReaderSurvivesBackgroundAndRelaunch() throws {
        try checkRestoration(tradition: "roman1954")
    }

    func testReaderRemainsAliveThroughBackgroundSuspension() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--suppress-app-tour", "-officeTradition", "roman1960",
            "-readerRestoration.tradition", "roman1960",
            "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2026-09-19",
            "-readerRestoration.hour", "compline",
            "-automaticOfficeSelectionEnabled", "NO"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 30))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        // An immediate activate() misses suspension-time terminations and
        // can silently relaunch a killed app. Check liveness before resuming.
        let suspended = expectation(description: "Allow background suspension")
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { suspended.fulfill() }
        wait(for: [suspended], timeout: 45)
        XCTAssertTrue([.runningBackground, .runningBackgroundSuspended].contains(app.state))
        app.activate()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 10))
    }

    private func checkRestoration(tradition: String) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--suppress-app-tour", "-officeTradition", tradition,
            "-readerRestoration.tradition", tradition,
            "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2026-09-10",
            "-readerRestoration.hour", "compline",
            "-readerRestoration.scrollOffset", "0",
            "-readerRestoration.scrollAnchor", "",
            "-automaticOfficeSelectionEnabled", "NO",
            "-prayerOptions.showsEnglish", "YES",
            "-prayerOptions.compactPsalmody", "NO"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.scrollViews["office-reader-scroll"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["office-reader-title"].isHittable)
        // Open through the UI so the session is written to persistent defaults;
        // launch argument defaults are deliberately removed for the relaunch.
        app.navigationBars.buttons["BackButton"].tap()
        if app.buttons["pray-selected-hour"].exists {
            app.buttons["pray-selected-hour"].tap()
        } else {
            app.buttons["hour-compline"].tap()
        }
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 30))
        let navigationTitle = app.navigationBars.firstMatch.identifier
        for swipes in [0, 1, 4] {
            for _ in 0..<swipes { app.swipeUp() }
            let marker = try visibleMarker(in: app)
            let originalY = marker.frame.minY
            let originalLabel = marker.label
            let identifier = marker.identifier
            let type = marker.elementType

            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            app.activate()
            XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 10))
            XCTAssertEqual(marker.frame.minY, originalY, accuracy: 5, "Background resume moved the prayer")

            if swipes == 4 {
                XCUIDevice.shared.press(.home)
                XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            }
            app.terminate()
            app.launchArguments = ["--suppress-app-tour", "-officeTradition", tradition,
                "-prayerOptions.showsEnglish", "YES", "-prayerOptions.compactPsalmody", "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.scrollViews["office-reader-scroll"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.navigationBars.firstMatch.identifier, navigationTitle)
            let restored = app.descendants(matching: type).matching(
                NSPredicate(format: "identifier == %@ AND label == %@", identifier, originalLabel)
            ).firstMatch
            XCTAssertTrue(restored.waitForExistence(timeout: 10), "The same prayer passage must return")
            let returnedToPosition = NSPredicate { _, _ in
                abs(restored.frame.minY - originalY) <= 5
            }
            expectation(for: returnedToPosition, evaluatedWith: restored)
            waitForExpectations(timeout: 8)
            XCTAssertEqual(restored.frame.minY, originalY, accuracy: 5, "Relaunch moved the prayer")
        }
    }

    private func visibleMarker(in app: XCUIApplication) throws -> XCUIElement {
        let candidates = app.descendants(matching: .any).matching(
            NSPredicate(format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.staticText.rawValue, XCUIElement.ElementType.textView.rawValue)
        ).allElementsBoundByIndex
        return try XCTUnwrap(candidates.first {
            !$0.label.isEmpty && $0.frame.minY > 150 && $0.frame.maxY < app.frame.maxY - 100 && $0.isHittable
                && app.descendants(matching: $0.elementType).matching(
                    NSPredicate(format: "identifier == %@ AND label == %@", $0.identifier, $0.label)
                ).count == 1
        }, "Expected a visible prayer passage to compare across relaunch")
    }
}
