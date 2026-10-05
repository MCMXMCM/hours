import XCTest

@MainActor
final class CantorGuideScrollingUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { UITestAppState.reset() }
    }

    func testCantorGuideStartsAndStopsRealPlayback() {
        let app = makeApplication()
        app.launchArguments += [
            "--ui-test-reader-score",
            "reference-2d499c8f414e9c81",
        ]
        app.launch()

        let selectedHour = app.buttons["hour-compline"]
        XCTAssertTrue(selectedHour.waitForExistence(timeout: 10))
        selectedHour.tap()

        let firstSalveReginaNeume = app.buttons[
            "reference-2d499c8f414e9c81-note-0"
        ]
        XCTAssertTrue(
            firstSalveReginaNeume.waitForExistence(timeout: 10)
                && firstSalveReginaNeume.isHittable
        )
        firstSalveReginaNeume.tap()

        let playbackButton = app.buttons["cantor-play"]
        if !playbackButton.waitForExistence(timeout: 5) {
            firstSalveReginaNeume.tap()
        }
        XCTAssertTrue(playbackButton.waitForExistence(timeout: 15))

        let sound = app.buttons["cantor-sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        sound.tap()
        let organ = app.buttons["Organ"]
        XCTAssertTrue(organ.waitForExistence(timeout: 3))
        organ.tap()
        XCTAssertEqual(sound.value as? String, "Organ")

        XCTAssertEqual(playbackButton.label, "Pause cantor guide")
        playbackButton.tap()

        let isStopped = NSPredicate(format: "label == %@", "Play cantor guide")
        expectation(for: isStopped, evaluatedWith: playbackButton)
        waitForExpectations(timeout: 5)

        playbackButton.tap()
        let isRestarted = NSPredicate(format: "label == %@", "Pause cantor guide")
        expectation(for: isRestarted, evaluatedWith: playbackButton)
        waitForExpectations(timeout: 5)

        playbackButton.tap()
        expectation(for: isStopped, evaluatedWith: playbackButton)
        waitForExpectations(timeout: 5)
    }

    func testCantorGuideKeepsSalveReginaPlaybackVisible() {
        let app = makeApplication()
        app.launchArguments += [
            "--ui-test-reader-score",
            "reference-2d499c8f414e9c81",
            "--ui-test-cantor-follow",
        ]
        app.launch()

        openOffice("compline", in: app)

        let firstSalveReginaNeume = app.buttons[
            "reference-2d499c8f414e9c81-note-0"
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
        if selectedHour.waitForExistence(timeout: 3) {
            selectedHour.tap()
            return
        } else {
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

    private func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        // Keep these playback checks independent of a previous test's restored
        // Office reader and the current clock's automatic hour selection.
        app.launchArguments = [
            "--suppress-app-tour",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
            "-readerRestoration.isPresented", "NO",
            "-automaticOfficeSelectionEnabled", "NO",
            "-manuallySelectedOfficeHour", "compline",
            "-hourSelectionView", "sunDial",
            // A previous test may have left Roman 1954 selected.
            "-officeTradition", "roman1960",
        ]
        return app
    }
}
