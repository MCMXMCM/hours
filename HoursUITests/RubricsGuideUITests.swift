import XCTest

@MainActor
final class RubricsGuideUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { UITestAppState.reset() }
    }

    private func openRubrics(edition: String? = "1960", arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-readerRestoration.isPresented", "NO"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["home-settings"].waitForExistence(timeout: 8))
        app.buttons["home-settings"].tap()
        app.buttons["settings-about"].tap()
        let entry = app.buttons["about-rubrics"]
        for _ in 0..<12 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        attach("About Rubrics entry", app)
        entry.tap()
        XCTAssertTrue(app.buttons["rubrics-edition-1960"].waitForExistence(timeout: 5))
        if let edition { selectEdition(edition, in: app) }
        return app
    }

    private func selectEdition(_ year: String, in app: XCUIApplication) {
        let entry = app.buttons["rubrics-edition-\(year)"]
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    private func search(_ text: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        field.tap()
        if field.buttons["Clear text"].exists {
            field.buttons["Clear text"].tap()
            // iPad's toolbar search field can resign focus when cleared.
            field.tap()
        }
        field.typeText(text + "\n")
    }

    private func openTopic(_ id: String, in app: XCUIApplication) {
        let topic = app.buttons["rubrics-topic-\(id)"]
        for _ in 0..<12 where !topic.isHittable { app.swipeUp() }
        XCTAssertTrue(topic.isHittable)
        topic.tap()
        XCTAssertTrue(app.scrollViews["rubrics-reader"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["rubrics-topic-title"].isHittable)
    }

    func testSearchFindsRulesAndReopeningStartsAtTheTop() {
        let app = openRubrics(arguments: [
            "-appearanceMode", "dynamic", "-automaticOfficeSelectionEnabled", "NO",
            "-manuallySelectedOfficeHour", "sext", "-hourSelectionView", "sunDial"
        ])
        attach("Rubrics topics", app)
        search("Psalm 4", in: app)
        XCTAssertFalse(app.buttons["rubrics-topic-classes"].exists)
        openTopic("compline", in: app)
        attach("Sunday Compline explanation", app)

        let source = app.descendants(matching: .any).matching(identifier:
            "rubrics-source-sunday-compline-Breviary Rubrics (1960), nos. 138, 167(b, h), 168(d)"
        ).firstMatch
        for _ in 0..<10 where !source.isHittable { app.scrollViews["rubrics-reader"].swipeUp() }
        XCTAssertTrue(source.isHittable)
        attach("Compline source references", app)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Psalm 4")
        openTopic("compline", in: app)
        XCTAssertTrue(app.staticTexts["rubrics-topic-title"].isHittable)
        app.navigationBars.buttons["BackButton"].tap()

        search("no-such-rubric-xyz", in: app)
        XCTAssertFalse(app.buttons["rubrics-topic-compline"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["rubrics-no-results"].exists)
        search("8G", in: app)
        openTopic("chant", in: app)
        let examples = app.buttons["rubrics-chant-guide"]
        for _ in 0..<18 where !examples.isHittable { app.scrollViews["rubrics-reader"].swipeUp() }
        XCTAssertTrue(examples.isHittable)
        examples.tap()
        XCTAssertTrue(app.buttons["chant-guide-glossary"].waitForExistence(timeout: 5))
        app.buttons["Reading the staff"].tap()
        XCTAssertTrue(app.scrollViews["chant-guide-reader"].waitForExistence(timeout: 3))
    }

    func testEditionChooserKeepsReferencesSeparate() {
        let app = openRubrics(edition: nil, arguments: [
            "-appearanceMode", "dynamic", "-automaticOfficeSelectionEnabled", "NO",
            "-manuallySelectedOfficeHour", "sext", "-hourSelectionView", "sunDial"
        ])
        let newer = app.buttons["rubrics-edition-1960"]
        let earlier = app.buttons["rubrics-edition-1954"]
        XCTAssertTrue(newer.isHittable)
        XCTAssertTrue(earlier.isHittable)
        XCTAssertLessThan(newer.frame.minY, earlier.frame.minY)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        attach("Rubrics edition chooser", app)

        selectEdition("1954", in: app)
        attach("1954 Rubrics topics", app)
        search("a capitulo", in: app)
        openTopic("vespers", in: app)
        XCTAssertEqual(app.staticTexts["rubrics-reader-edition"].label, "Roman Office · 1954 rubrics")
        let source = app.descendants(matching: .any).matching(identifier:
            "rubrics-source-divided-vespers-Additions to the Roman Breviary, tit. VI, nos. 1–4"
        ).firstMatch
        for _ in 0..<12 where !source.isHittable { app.scrollViews["rubrics-reader"].swipeUp() }
        XCTAssertTrue(source.isHittable)
        attach("1954 divided Vespers and citations", app)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "a capitulo")
        search("Sources", in: app)
        openTopic("sources", in: app)
        XCTAssertEqual(app.staticTexts["rubrics-reader-edition"].label, "Roman Office · 1954 rubrics")
        attach("1954 sources", app)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Sources")
        // iPhone's active native search hides the navigation bar. Leave search
        // before navigating out of the edition; iPad can keep its bar visible.
        if app.buttons["close"].isHittable {
            app.buttons["close"].tap()
        } else if app.buttons["Cancel"].isHittable {
            app.buttons["Cancel"].tap()
        }
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["rubrics-edition-1960"].waitForExistence(timeout: 5))

        selectEdition("1960", in: app)
        XCTAssertNotEqual(app.searchFields.firstMatch.value as? String, "Sources")
        search("four classes", in: app)
        openTopic("classes", in: app)
        XCTAssertEqual(app.staticTexts["rubrics-reader-edition"].label, "Roman Office · 1960 rubrics")
        XCTAssertEqual(app.staticTexts["rubrics-topic-title"].label, "The four classes of liturgical days")
        app.navigationBars.buttons["BackButton"].tap()
        search("Sources", in: app)
        openTopic("sources", in: app)
        XCTAssertEqual(app.staticTexts["rubrics-reader-edition"].label, "Roman Office · 1960 rubrics")
    }

    func testLargeTextDarkReaderAccessibility() throws {
        let app = openRubrics(edition: "1954", arguments: [
            "-appearanceMode", "dynamic", "-automaticOfficeSelectionEnabled", "NO",
            "-manuallySelectedOfficeHour", "compline", "-hourSelectionView", "sunDial",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        search("First Vespers", in: app)
        openTopic("vespers", in: app)
        attach("Rubrics large text dark", app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.scrollViews["rubrics-reader"].exists)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        if app.frame.width > app.frame.height {
            attach("Rubrics wide layout", app)
        }
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
