import XCTest

@MainActor
final class ChantGuideUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { UITestAppState.reset() }
    }

    private func openGuide(additionalArguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-readerRestoration.isPresented", "NO"] + additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["home-settings"].waitForExistence(timeout: 8))
        app.buttons["home-settings"].tap()
        app.buttons["settings-about"].tap()
        let guide = app.buttons["about-chant-guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 3))
        for _ in 0..<3 where !guide.isHittable { app.swipeUp() }
        guide.tap()
        XCTAssertTrue(app.buttons["chant-guide-glossary"].waitForExistence(timeout: 5))
        return app
    }

    private func showTopics(_ app: XCUIApplication) {
        if app.scrollViews["chant-guide-reader"].exists {
            app.navigationBars.buttons["BackButton"].tap()
        }
        XCTAssertTrue(app.buttons["chant-guide-glossary"].waitForExistence(timeout: 3))
    }

    private func jump(_ section: String, in app: XCUIApplication) {
        showTopics(app)
        let lesson = app.buttons[section]
        let topics = app.descendants(matching: .any).matching(identifier: "chant-guide-topics").firstMatch
        for _ in 0..<12 where !(lesson.exists && lesson.isHittable) { topics.swipeUp() }
        for _ in 0..<12 where !(lesson.exists && lesson.isHittable) { topics.swipeDown() }
        XCTAssertTrue(lesson.isHittable)
        lesson.tap()
        XCTAssertTrue(app.scrollViews["chant-guide-reader"].waitForExistence(timeout: 3))
    }

    func testTopicsOpenOnlyTheSelectedLessonAndBackReturnsToTopics() {
        let app = openGuide()
        XCTAssertFalse(app.scrollViews["chant-guide-reader"].exists)
        XCTAssertFalse(app.buttons["guide-play-staff-scale"].exists)
        attach("Guide topic menu", app)
        for topic in ["Reading the staff", "Pitch and modes", "Recognizing neumes",
                      "Special signs and interpretation", "Phrasing and breathing",
                      "Understanding rhythm", "Chanting psalms", "Psalm tones and their endings", "Latin pronunciation",
                      "Singing together and source notes"] {
            jump(topic, in: app)
            XCTAssertTrue(app.navigationBars[topic].exists)
            if topic != "Reading the staff" {
                XCTAssertFalse(app.buttons["guide-play-staff-scale"].exists)
            }
            if topic != "Recognizing neumes" {
                XCTAssertFalse(app.buttons["guide-play-punctum"].exists)
            }
            showTopics(app)
            XCTAssertFalse(app.scrollViews["chant-guide-reader"].exists)
            XCTAssertFalse(app.buttons["cantor-play"].exists)
        }
    }

    func testAboutEntryContentsSilentSelectionAndPlayback() {
        let app = openGuide()
        jump("Reading the staff", in: app)
        let play = app.buttons["guide-play-clef-staff-positions"]
        for _ in 0..<7 where !play.isHittable { scrollReader(app) }
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(app.buttons["cantor-play"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["cantor-play"].label, "Play cantor guide")
        app.buttons["cantor-options"].tap()
        XCTAssertTrue(app.sliders["tempo-slider"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["cantor-schola-pitch"].exists)
        XCTAssertTrue(app.buttons["cantor-register"].exists)
        XCTAssertTrue(app.buttons["cantor-sound"].exists)
        XCTAssertFalse(app.buttons["Loop phrase"].exists)
        XCTAssertFalse(app.switches["Loop phrase"].exists)
        app.buttons["Done"].tap()
        play.tap()
        XCTAssertEqual(app.buttons["cantor-play"].label, "Pause cantor guide")
        app.buttons["cantor-close"].tap()
        XCTAssertFalse(app.buttons["cantor-play"].exists)
        scrollReader(app)
        XCTAssertFalse(app.buttons["cantor-play"].exists)
        jump("Chanting psalms", in: app)
        XCTAssertTrue(app.buttons["guide-play-psalm-verse"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Pause cantor guide"].exists)
        attach("Guide psalmody", app)
    }

    func testComparisonsExplorationPronunciationAndGlossary() {
        let app = openGuide()
        jump("Reading the staff", in: app)
        let staffPositions = app.buttons["guide-variant-tab-guide-clef-staff-positions-c2"]
        for _ in 0..<20 where !staffPositions.isHittable { scrollReader(app) }
        XCTAssertTrue(staffPositions.isHittable)
        let staffExplore = app.buttons["guide-explore-clef-staff-positions"]
        for _ in 0..<4 where !staffExplore.isHittable { scrollReader(app) }
        attach("C clef on the fourth line", app)
        for title in ["C clef · third line", "C clef · second line"] {
            app.buttons[title].tap()
            attach(title, app)
        }
        let comparison = app.buttons["guide-variant-clef-equivalence"]
        for _ in 0..<24 where !comparison.isHittable { scrollReader(app) }
        XCTAssertTrue(comparison.isHittable)
        comparison.tap()
        app.buttons["F clef · third line"].tap()
        XCTAssertEqual(app.buttons["cantor-play"].label, "Play cantor guide")
        let explore = app.buttons["guide-explore-clef-equivalence"]
        for _ in 0..<3 where !explore.isHittable { scrollReader(app) }
        explore.tap()
        let firstDo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Note 1, Do'")).firstMatch
        for _ in 0..<6 where !firstDo.isHittable { scrollReader(app) }
        XCTAssertTrue(firstDo.isHittable)
        attach("Guide clef exploration", app)
        jump("Latin pronunciation", in: app)
        let vowels = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pure vowels'")).firstMatch
        for _ in 0..<7 where !vowels.isHittable { scrollReader(app) }
        XCTAssertTrue(vowels.isHittable)
        vowels.tap()
        attach("Guide Latin pronunciation", app)
        showTopics(app)
        app.buttons["chant-guide-glossary"].tap()
        let clef = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Clef' ")).firstMatch
        XCTAssertTrue(clef.waitForExistence(timeout: 3))
        clef.tap()
        XCTAssertTrue(app.navigationBars["Reading the staff"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["guide-play-clef-staff-positions"].isHittable)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pure vowels'")).firstMatch.exists)
    }

    func testSelectedLessonsAlwaysOpenAtTheTop() {
        let app = openGuide()
        jump("Latin pronunciation", in: app)
        let title = app.staticTexts["chant-guide-lesson-title"]
        XCTAssertTrue(title.isHittable)
        let top = title.frame.minY

        for _ in 0..<3 { scrollReader(app) }
        XCTAssertFalse(title.isHittable)
        jump("Latin pronunciation", in: app)
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.frame.minY, top, accuracy: 2)

        for _ in 0..<3 { scrollReader(app) }
        XCTAssertFalse(title.isHittable)
        jump("Pitch and modes", in: app)
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.frame.minY, top, accuracy: 2)
        showTopics(app)
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["about-chant-guide"].tap()
        XCTAssertTrue(app.buttons["chant-guide-glossary"].waitForExistence(timeout: 3))
        jump("Latin pronunciation", in: app)
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.frame.minY, top, accuracy: 2)
    }

    func testPsalmToneNotationAndEndingComparisons() {
        let app = openGuide()
        jump("Psalm tones and their endings", in: app)
        XCTAssertTrue(app.buttons["guide-play-tone-eight-g"].isHittable)
        for id in ["tone-eight-g", "tone-one-a3", "tone-one-endings", "tone-euouae"] {
            let play = app.buttons["guide-play-\(id)"]
            for _ in 0..<35 where !play.isHittable { scrollReader(app) }
            XCTAssertTrue(play.isHittable, id)
            attach("Psalm tones \(id)", app)
            if id == "tone-one-endings" {
                let picker = app.buttons["guide-variant-\(id)"]
                let tab = app.buttons["guide-variant-tab-guide-tone-one-endings-a3"]
                for _ in 0..<4 where !(picker.isHittable || tab.isHittable) { scrollReader(app) }
                if picker.isHittable { picker.tap() }
                app.buttons["Ending a³"].tap()
                XCTAssertEqual(app.buttons["cantor-play"].label, "Play cantor guide")
                attach("Psalm tones selected a3", app)
            }
        }
    }

    func testVariantTabsSelectNotesAndFallBackToMenuForLargeText() {
        let app = openGuide()
        jump("Reading the staff", in: app)
        let fourth = app.buttons["guide-variant-tab-guide-clef-staff-positions-c4"]
        let third = app.buttons["guide-variant-tab-guide-clef-staff-positions-c3"]
        let second = app.buttons["guide-variant-tab-guide-clef-staff-positions-c2"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 3))
        XCTAssertTrue(fourth.isHittable && third.isHittable && second.isHittable)
        XCTAssertLessThan(fourth.frame.minX, third.frame.minX)
        XCTAssertLessThan(third.frame.minX, second.frame.minX)
        XCTAssertTrue(fourth.isSelected)
        XCTAssertFalse(second.isSelected)
        second.tap()
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(fourth.isSelected)
        third.tap()
        XCTAssertTrue(third.isSelected)
        attach("Guide variant tabs", app)
        app.terminate()

        let largeTextApp = openGuide(additionalArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        jump("Reading the staff", in: largeTextApp)
        let menu = largeTextApp.buttons["guide-variant-clef-staff-positions"]
        for _ in 0..<12 where !menu.isHittable { scrollReader(largeTextApp) }
        XCTAssertTrue(menu.isHittable)
        XCTAssertFalse(largeTextApp.buttons["guide-variant-tab-guide-clef-staff-positions-c4"].exists)
        XCTAssertTrue(menu.label.contains("fourth line"))
        menu.tap()
        largeTextApp.buttons["C clef · second line"].tap()
        XCTAssertTrue(menu.label.contains("second line"))
        attach("Guide variant menu at large text", largeTextApp)
    }

    func testLargeTextNotationAndAccessibleDescriptions() throws {
        let app = openGuide(additionalArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-automaticOfficeSelectionEnabled", "NO", "-manuallySelectedOfficeHour", "sext",
            "-hourSelectionView", "sunDial"
        ])
        jump("Recognizing neumes", in: app)
        let play = app.buttons["guide-play-punctum"]
        for _ in 0..<24 where !play.isHittable { scrollReader(app) }
        XCTAssertTrue(play.isHittable)
        let explore = app.buttons["guide-explore-punctum"]
        for _ in 0..<12 where !explore.isHittable { scrollReader(app) }
        XCTAssertTrue(explore.isHittable)
        explore.tap()
        let note = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Note 1, Do'")).firstMatch
        for _ in 0..<6 where !note.isHittable { scrollReader(app) }
        XCTAssertTrue(note.isHittable)
        attach("Guide large text and notation", app)
        try app.performAccessibilityAudit(for: .sufficientElementDescription)
    }

    func testNightAppearanceRotationAndBackgroundStopsPlayback() {
        let app = openGuide(additionalArguments: [
            "-appearanceMode", "dynamic",
            "-automaticOfficeSelectionEnabled", "NO",
            "-manuallySelectedOfficeHour", "compline",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ])
        jump("Reading the staff", in: app)
        let play = app.buttons["guide-play-clef-staff-positions"]
        for _ in 0..<8 where !play.isHittable { scrollReader(app) }
        XCTAssertTrue(play.isHittable)
        attach("Guide night appearance", app)
        play.tap()
        XCTAssertEqual(app.buttons["cantor-play"].label, "Pause cantor guide")
        XCUIDevice.shared.press(.home)
        app.activate()
        let stopped = NSPredicate(format: "label == %@", "Play cantor guide")
        expectation(for: stopped, evaluatedWith: app.buttons["cantor-play"])
        waitForExpectations(timeout: 5)

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        jump("Chanting psalms", in: app)
        XCTAssertTrue(app.buttons["guide-play-psalm-verse"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Pause cantor guide"].exists)
        attach("Guide landscape contents jump", app)
    }

    private func scrollReader(_ app: XCUIApplication) {
        let reader = app.scrollViews["chant-guide-reader"]
        let bounds = reader.frame
        let controls = app.otherElements["chant-guide-controls"]
        let top = max(bounds.minY, app.navigationBars.firstMatch.frame.maxY)
        let bottom = controls.exists ? min(bounds.maxY, controls.frame.minY) : bounds.maxY
        let height = max(60, bottom - top)
        let start = (top + height * 0.85 - bounds.minY) / bounds.height
        let end = (top + height * 0.25 - bounds.minY) / bounds.height
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
            .press(forDuration: 0.05, thenDragTo: reader.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: end)
            ), withVelocity: .slow, thenHoldForDuration: 0.15)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
