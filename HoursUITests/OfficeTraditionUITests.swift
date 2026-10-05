import XCTest

@MainActor
final class OfficeTraditionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { UITestAppState.reset() }
    }

    func testRestoredSeasonalComplineHymnsRenderFromOpeningThroughAmen() {
        let app = XCUIApplication()
        for (date, hash, lastNote) in [
            ("2025-08-19", "5a14eb89c529bcd0d92af4bd78bb527f4f35d889cc37300d8af4d7f36151b2f9", 151),
            ("2025-05-13", "0094811d76476220c0c06e9ced1a52de5515bf1e649c489fc9f76e4feb272db6", 112),
            ("2025-06-03", "567fb3c8d035174587bd9d3096f9c1afc726d207c230a5b0b2818e8cdaed9312", 150),
            ("2025-12-02", "0c9b2eb69333866f5857a2f2ea5a6a53266ba5703a3027a1e5f6151f62b8116c", 135)
        ] {
            app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
                "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
                "-readerRestoration.day", date, "-readerRestoration.hour", "compline",
                "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "",
                "-prayerOptions.showsEnglish", "YES", "-prayerOptions.compactPsalmody", "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
            app.buttons["office-sections"].tap()
            XCTAssertTrue(app.buttons["office-sections-close"].waitForExistence(timeout: 5))
            let hymn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jump to Hymnus")).firstMatch
            for _ in 0..<8 {
                if hymn.exists && hymn.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(hymn.exists && hymn.isHittable)
            hymn.tap()
            let opening = app.buttons["roman1954-\(hash)-note-0"]
            XCTAssertTrue(opening.waitForExistence(timeout: 10) && opening.isHittable)
            let heading = app.staticTexts["HYMNUS"]
            XCTAssertTrue(heading.exists && heading.isHittable, "The jump must show the hymn's heading and opening")
            XCTAssertGreaterThan(heading.frame.minY, app.buttons["office-sections"].frame.maxY)
            attach(date + " Te lucis opening", app)
            let amen = app.buttons["roman1954-\(hash)-note-\(lastNote)"]
            for _ in 0..<8 {
                if amen.exists && amen.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(amen.exists && amen.isHittable)
            XCTAssertFalse(app.staticTexts["The chant layout was not prepared."].exists)
            attach(date + " Te lucis conclusion and Amen", app)
            app.terminate()
        }
    }

    func testSeptember15ComplinePsalmHeadingsAndCompleteHymnInBothReadingModes() {
        let app = XCUIApplication()
        let hymnID = "roman1954-f81a5b2925cb89ac70fc2262aeead19f00dee35d66944a3c8651096ef5e0fae0"
        for compact in [false, true] {
            app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
                "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
                "-readerRestoration.day", "2026-09-15", "-readerRestoration.hour", "compline",
                "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "",
                "-prayerOptions.showsEnglish", compact ? "NO" : "YES",
                "-prayerOptions.compactPsalmody", compact ? "YES" : "NO"]
            app.launch()
            func jump(to title: String) {
                XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
                app.buttons["office-sections"].tap()
                XCTAssertTrue(app.buttons["office-sections-close"].waitForExistence(timeout: 5))
                let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jump to " + title)).firstMatch
                for _ in 0..<8 {
                    if entry.exists && entry.isHittable { break }
                    app.swipeUp()
                }
                XCTAssertTrue(entry.exists && entry.isHittable, title)
                entry.tap()
            }
            jump(to: "Psalmus 4")
            XCTAssertTrue(app.staticTexts["Psalmus 4"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Psalmi"].exists)
            XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value BEGINSWITH %@", "Psalmus 4")).firstMatch.exists)
            attach("September 15 Psalm 4 — " + (compact ? "compact Latin" : "full bilingual"), app)
            jump(to: "Hymnus")
            let opening = app.buttons[hymnID + "-note-0"]
            XCTAssertTrue(opening.waitForExistence(timeout: 10))
            XCTAssertTrue(opening.isHittable)
            attach("September 15 Te lucis opening — " + (compact ? "Latin" : "bilingual"), app)
            // A neume's accessibility ID is its first note, not its last.
            let amen = app.buttons[hymnID + "-note-141"]
            for _ in 0..<8 {
                if amen.exists && amen.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(amen.exists && amen.isHittable, "The proper conclusion and Amen must remain scored")
            XCTAssertFalse(app.staticTexts["The chant layout was not prepared."].exists)
            attach("September 15 Te lucis proper conclusion and Amen — " + (compact ? "Latin" : "bilingual"), app)
            app.terminate()
        }
    }

    func testRoman1954ComplineDisplaysRubricsAndPsalmHeadingsCleanly() {
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
            "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2026-09-10", "-readerRestoration.hour", "compline",
            "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES",
            "-prayerOptions.compactPsalmody", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
        app.buttons["office-sections"].tap()
        let psalms = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jump to Psalmus 69")).firstMatch
        XCTAssertTrue(psalms.waitForExistence(timeout: 5))
        psalms.tap()
        let heading = app.staticTexts["Psalmus 69"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertFalse((heading.value as? String ?? heading.label).contains("[1]"))
        XCTAssertFalse(app.staticTexts["Psalmi"].exists)
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "{ex Psalterio")).firstMatch.exists)
        attach("Roman 1954 Compline clean source rubric and psalm heading", app)
    }

    func testSeptember10ComplineShowsPsalm70AndInManusTuasNotation() {
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
            "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2026-09-10", "-readerRestoration.hour", "compline",
            "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES"]
        app.launch()
        let targets = [
            ("Psalmus 70", 0, "roman1954-decabc32ab39cd92f0caa4795b1c696040d98d576c86327605a779a0ff5a20c4", "Psalm 70 first division"),
            ("Psalmus 70", 1, "roman1954-5b9cc19dd8f19a7f642d645fbdf6a92029e0cfbed6d27c2f827a4c678ca2f2d8", "Psalm 70 second division"),
            ("Capitulum", 0, "roman1954-d6e22df5817e65b6897f6406b7ad18328b43c33db75c902d9a0e27044ce10bec", "In manus tuas")
        ]
        for (title, index, scoreID, name) in targets {
            XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
            app.buttons["office-sections"].tap()
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jump to " + title)).element(boundBy: index)
            // Wait for the sheet before scrolling its ordered entries. A
            // downward swipe at the top dismisses the sheet on iPhone.
            XCTAssertTrue(app.buttons["office-sections-close"].waitForExistence(timeout: 5))
            for _ in 0..<8 {
                if entry.exists && entry.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            let note = app.buttons[scoreID + "-note-0"]
            for _ in 0..<5 {
                if note.waitForExistence(timeout: 2) && note.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(note.exists && note.isHittable, name)
            XCTAssertFalse(app.staticTexts["The chant layout was not prepared."].exists)
            attach(name, app)
        }
    }

    func testRoman1954HolySaturdayHeadingAndSoloRubricPresentation() {
        let app = XCUIApplication()
        func open(_ date: String, _ hour: String) {
            app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
                "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
                "-readerRestoration.day", date, "-readerRestoration.hour", hour,
                "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES"]
            app.launch()
            XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
        }
        open("2026-04-04", "vespers")
        XCTAssertTrue(app.staticTexts["VESPERÆ SABBATI SANCTI"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Holy Saturday Vespers"].firstMatch.exists)
        attach("Holy Saturday Vespers corrected bilingual heading", app)
        app.buttons["office-sections"].tap()
        XCTAssertFalse(app.buttons["Jump to P"].exists)
        XCTAssertFalse(app.buttons["Jump to Q"].exists)
        app.terminate()
        open("2026-09-10", "compline")
        let translation = "Outside choir, when the Office is recited by one person alone, Jube, Dómine, benedícere is said; the appropriate blessing follows."
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", translation)).firstMatch.waitForExistence(timeout: 10))
        attach("Compline solo direction with bilingual rubric typography", app)
    }

    func testPassiontideResponseShowsNotationAndBilingualOmissionDirection() {
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
            "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2025-04-13", "-readerRestoration.hour", "compline",
            "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
        app.buttons["office-sections"].tap()
        let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jump to Capitulum")).firstMatch
        for _ in 0..<5 {
            if chapter.exists && chapter.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        let note = app.buttons["roman1954-a11fe8f529921eddfbb5a81ef0911e2d25e40b9f402365068f8663cb01f3f478-note-0"]
        for _ in 0..<5 {
            if note.exists && note.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gloria omittitur"].exists)
        XCTAssertTrue(app.staticTexts["omit Glory be"].exists)
        XCTAssertFalse(app.staticTexts["The chant layout was not prepared."].exists)
        attach("Passiontide response with bilingual omission direction", app)
    }

    func testRoman1954ClericalGreetingReplacesTheScoredLayForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
            "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2026-09-07", "-readerRestoration.hour", "vespers",
            "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES",
            "-prayerOptions.priestOrDeaconPresent", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
        app.buttons["office-sections"].tap()
        let oratio = app.buttons["tour-reader-oratio"].firstMatch
        for _ in 0..<8 {
            if oratio.exists && oratio.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(oratio.waitForExistence(timeout: 5))
        oratio.tap()
        let layNote = app.buttons["roman1954-777c0d80d6cc8b9654652c0bfd31df0661aa0ce95a9667c1363152d3787868eb-note-0"]
        XCTAssertTrue(layNote.waitForExistence(timeout: 10))
        app.buttons["prayer-options"].tap()
        app.buttons["priest-or-deacon-present"].tap()
        app.buttons["Yes"].tap()
        app.buttons["prayer-options-close"].tap()
        let latin = app.textViews.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Dóminus vobíscum", "Dóminus vobíscum")).firstMatch
        XCTAssertTrue(latin.waitForExistence(timeout: 10))
        let english = app.textViews.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "The Lord be with you", "The Lord be with you")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertFalse(layNote.exists)
        attach("Roman 1954 clerical greeting with text fallback", app)
        app.buttons["prayer-options"].tap()
        app.buttons["priest-or-deacon-present"].tap()
        app.buttons["No"].tap()
        app.buttons["prayer-options-close"].tap()
        XCTAssertTrue(layNote.waitForExistence(timeout: 10))
    }

    func testSeptember8ComplineBlessingNotationAndHeaderOrderInRoman1954() {
        let app = XCUIApplication()
        for (tradition, title, scorePrefix) in [
            ("roman1954", "Roman 1954", "roman1954")
        ] {
            app.launchArguments = ["--suppress-app-tour", "-officeTradition", tradition,
                "-readerRestoration.tradition", tradition, "-readerRestoration.isPresented", "YES",
                "-readerRestoration.day", "2026-09-08", "-readerRestoration.hour", "compline",
                "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES"]
            app.launch()
            let edition = app.staticTexts["office-tradition-label"]
            let rank = app.staticTexts["office-rank-label"]
            XCTAssertTrue(edition.waitForExistence(timeout: 15))
            XCTAssertEqual(edition.label, title)
            XCTAssertLessThan(rank.frame.maxY, edition.frame.minY)
            attach("\(title) class above rubrics", app)
            // The actual source blessing's first and final neumes, rather
            // than any score somewhere in Compline.
            let score = "\(scorePrefix)-311407f5174d9f89d053ac4d1cdb37b139d0d79a364b440f378887b1b11801fa"
            let blessing = app.buttons["\(score)-note-0"]
            for _ in 0..<4 {
                if blessing.exists && blessing.frame.midY < app.frame.maxY - 100 { break }
                app.swipeUp()
            }
            XCTAssertTrue(blessing.exists, "The blessing itself must render a score")
            XCTAssertTrue(app.buttons["\(score)-note-24"].exists, "The blessing's Amen must retain its notation")
            XCTAssertFalse(app.staticTexts["The chant layout was not prepared."].exists)
            attach("\(title) September 8 blessing notation", app)
            app.terminate()
        }
    }

    func testBothRomanEditionsSwitchAndRoman1954PersistsAfterRelaunch() {
        let app = XCUIApplication()
        let arguments = ["--suppress-app-tour", "-readerRestoration.isPresented", "NO",
            "-automaticOfficeSelectionEnabled", "NO", "-manuallySelectedOfficeHour", "vespers"]
        app.launchArguments = arguments + ["-officeTradition", "roman1960"]
        app.launch()
        XCTAssertTrue(app.buttons["home-settings"].waitForExistence(timeout: 10))
        app.buttons["home-settings"].tap()
        let picker = app.segmentedControls["office-tradition-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.buttons.count, 2)
        XCTAssertFalse(picker.buttons["Benedictine 1963"].exists)
        XCTAssertTrue(app.staticTexts["Rubrics"].exists)
        var settledPickerFrame: CGRect?
        for title in ["Roman 1954", "Roman 1960", "Roman 1954"] {
            // The selected label updates before the calendar snapshot finishes.
            // Wait for the picker to accept input before the next switch.
            expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: picker.buttons[title])
            waitForExpectations(timeout: 20)
            picker.buttons[title].tap()
            let selected = NSPredicate(format: "isSelected == true")
            expectation(for: selected, evaluatedWith: picker.buttons[title])
            waitForExpectations(timeout: 10)
            if let frame = settledPickerFrame {
                XCTAssertEqual(picker.frame.minY, frame.minY, accuracy: 1, "Rubric switching must not shift the settings layout")
            } else {
                settledPickerFrame = picker.frame
            }
            XCTAssertFalse(app.staticTexts["office-tradition-error"].exists)
        }
        XCTAssertFalse(app.staticTexts["clear-creek-calendar-note"].exists)
        attach("Roman 1954 settings", app)
        app.buttons["settings-close"].tap()
        XCTAssertEqual(app.staticTexts["home-office-tradition"].label, "Roman 1954")
        attach("Roman 1954 home header", app)
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["home-office-tradition"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["home-office-tradition"].label, "Roman 1954")
        if app.buttons["pray-selected-hour"].exists {
            app.buttons["pray-selected-hour"].tap()
        } else { app.buttons["hour-vespers"].tap() }
        XCTAssertTrue(app.staticTexts["office-tradition-label"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["office-tradition-label"].label, "Roman 1954")
        attach("Roman 1954 Vespers", app)
    }

    func testRoman1954CompactComplineShowsLaterVersesAsProse() {
        let app = XCUIApplication()
        app.launchArguments = ["--suppress-app-tour", "-officeTradition", "roman1954",
            "-readerRestoration.tradition", "roman1954", "-readerRestoration.isPresented", "YES",
            "-readerRestoration.day", "2026-09-10", "-readerRestoration.hour", "compline",
            "-readerRestoration.scrollOffset", "0", "-readerRestoration.scrollAnchor", "", "-prayerOptions.showsEnglish", "YES",
            "-prayerOptions.compactPsalmody", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["office-sections"].waitForExistence(timeout: 20))
        app.buttons["office-sections"].tap()
        // The outline lists each psalm of the source-ordered Office.
        let psalms = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jump to Psalmus 69")).firstMatch
        XCTAssertTrue(psalms.waitForExistence(timeout: 5))
        psalms.tap()
        let continuation = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "2. Confundántur")).firstMatch
        // The jump lands on the psalm before its later verses are laid out;
        // wait for them rather than swiping past.
        // Lazy layout can also leave the page past it, so steer by its position.
        _ = continuation.waitForExistence(timeout: 5)
        for _ in 0..<8 {
            if continuation.exists && continuation.isHittable { break }
            if continuation.exists && continuation.frame.maxY < app.frame.midY {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(continuation.exists && continuation.isHittable)
        XCTAssertFalse(app.staticTexts["The chant layout was not prepared."].exists)
        attach("Roman 1954 compact Psalm 69 with later verses as prose", app)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
