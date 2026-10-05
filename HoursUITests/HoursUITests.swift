import XCTest

@MainActor
final class HoursUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { UITestAppState.reset() }
    }

    func testSelectablePrayerTextInteraction() {
        let app = makeApplication()
        // On a day whose Hour is sung from its opening, the translation is the
        // first prose on the page.
        app.launchArguments += ["-prayerOptions.showsEnglish", "YES"]
        app.launch()

        openSundialOffice("prime", in: app)
        XCTAssertTrue(
            app.staticTexts["office-reader-title"].waitForExistence(timeout: 5)
        )

        // Take a paragraph whose first line is on screen; a long one's centre
        // may lie below the screen.
        let reader = app.scrollViews["office-reader-scroll"]
        let paragraphs = app.textViews.matching(identifier: "selectable-prayer-text")
        var visibleParagraph: XCUIElement?
        for _ in 0..<12 {
            visibleParagraph = paragraphs.allElementsBoundByIndex.first {
                $0.frame.minY > 150 && $0.frame.minY < app.frame.maxY - 200
            }
            if visibleParagraph != nil { break }
            reader.swipeUp()
        }
        guard let paragraph = visibleParagraph else {
            return XCTFail("No prayer paragraph became visible")
        }

        paragraph.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 40, dy: 12))
            .press(forDuration: 1)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Selectable prayer text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPrayerAlwaysStartsAtTop() {
        let app = makeApplication()
        selectHourOnLaunch("lauds", in: app)
        app.launch()

        openSundialOffice("lauds", in: app)

        let readerTop = app.staticTexts["office-reader-title"]
        XCTAssertTrue(readerTop.waitForExistence(timeout: 5))
        XCTAssertTrue(readerTop.isHittable)

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(readerTop.isHittable)

        app.navigationBars.buttons.firstMatch.tap()
        openSundialOffice("lauds", in: app)
        XCTAssertTrue(readerTop.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(readerTop.isHittable)
    }

    func testOfficeSectionsSheetOpensFromButtonAndJumps() {
        let app = makeApplication()
        app.launch()

        let praySelectedHour = app.buttons["pray-selected-hour"]
        if praySelectedHour.waitForExistence(timeout: 1) {
            praySelectedHour.tap()
        } else {
            openSundialOffice("prime", in: app)
        }
        XCTAssertTrue(
            app.staticTexts["office-reader-title"]
                .waitForExistence(timeout: 5)
        )

        let sectionsButton = app.buttons["office-sections"]
        let optionsButton = app.buttons["prayer-options"]
        XCTAssertTrue(sectionsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(optionsButton.exists)
        XCTAssertLessThan(
            sectionsButton.frame.midX,
            optionsButton.frame.midX,
            "The sections button should appear to the left of Prayer options."
        )

        sectionsButton.tap()
        let sheetNavigationBar = app.navigationBars["Office sections"]
        XCTAssertTrue(sheetNavigationBar.waitForExistence(timeout: 3))
        let closeButton = app.buttons["office-sections-close"]
        XCTAssertTrue(closeButton.exists)

        let firstJump = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "office-outline-jump-"
            )
        ).firstMatch
        XCTAssertTrue(firstJump.waitForExistence(timeout: 3))
        let headingIdentifier = firstJump.identifier.replacingOccurrences(
            of: "office-outline-jump-",
            with: "office-section-heading-"
        )
        firstJump.tap()
        XCTAssertTrue(
            sheetNavigationBar.waitForNonExistence(timeout: 3)
        )
        let heading = app.staticTexts[headingIdentifier]
        XCTAssertTrue(
            heading.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(heading.isHittable)

        sectionsButton.tap()
        XCTAssertTrue(sheetNavigationBar.waitForExistence(timeout: 3))
        closeButton.tap()
        XCTAssertTrue(
            sheetNavigationBar.waitForNonExistence(timeout: 3)
        )
    }

    func testSelectedHourShowsBundledNotationImmediately() {
        let app = makeApplication()
        selectHourOnLaunch("lauds", in: app)
        app.launch()

        openSundialOffice("lauds", in: app)
        XCTAssertTrue(app.staticTexts["office-reader-title"].waitForExistence(timeout: 5))

        let firstImportedNeume = firstRenderedNeume(in: app)
        XCTAssertTrue(
            firstImportedNeume.waitForExistence(timeout: 10),
            "The selected hour should render its first imported chant before the office text."
        )
    }

    func testCompactComplinePsalmShowsLaterVersesAsProse() {
        let app = makeApplication()
        app.launchArguments += [
            "-readerRestoration.isPresented",
            "YES",
            "-readerRestoration.day",
            "2026-08-29",
            "-readerRestoration.hour",
            "compline",
            "-readerRestoration.scrollOffset",
            "0",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["office-reader-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["translation-toggle"].exists)
        app.buttons["prayer-options"].tap()
        let translationToggle = app.switches["translation-toggle"]
        XCTAssertTrue(translationToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(translationToggle.value as? String, "0")
        setSwitch(translationToggle, on: true)
        let compactPsalmodyToggle = app.switches["compact-psalmody-toggle"]
        XCTAssertTrue(compactPsalmodyToggle.exists)
        XCTAssertEqual(compactPsalmodyToggle.value as? String, "0")
        setSwitch(compactPsalmodyToggle, on: true)
        app.buttons["prayer-options-close"].tap()

        // A second sheet cannot be presented while the first is closing.
        let sectionsSheet = app.navigationBars["Office sections"]
        for _ in 0..<3 where !sectionsSheet.exists {
            app.buttons["office-sections"].tap()
            _ = sectionsSheet.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(sectionsSheet.exists)
        // The psalm's entry begins at its antiphon, so find it by name.
        let psalm87Jump = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Jump to Psalmus 87")
        ).firstMatch
        XCTAssertTrue(psalm87Jump.waitForExistence(timeout: 5))
        for _ in 0..<12 where !psalm87Jump.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(psalm87Jump.isHittable)
        psalm87Jump.tap()

        let psalm87SecondVerse = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "2. Intret in conspéctu tuo"
            )
        ).firstMatch
        for _ in 0..<6 where !psalm87SecondVerse.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(psalm87SecondVerse.isHittable)

        app.buttons["office-sections"].tap()
        let psalm102SecondHalfJump = app.buttons[
            "office-outline-jump-2026-08-29-compline-section-22"
        ]
        for _ in 0..<12 where !psalm102SecondHalfJump.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(psalm102SecondHalfJump.isHittable)
        psalm102SecondHalfJump.tap()

        let psalm102MissingEnglishVerse = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "2. Recordátus est"
                )
            ).firstMatch
        for _ in 0..<6 where !psalm102MissingEnglishVerse.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(psalm102MissingEnglishVerse.isHittable)

        let psalm102FollowingEnglish = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "For the spirit shall pass in him"
                )
            ).firstMatch
        for _ in 0..<3 where !psalm102FollowingEnglish.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(psalm102FollowingEnglish.isHittable)
        let psalm102FollowingLatin = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "3. Quóniam spíritus"
                )
            ).firstMatch
        XCTAssertTrue(psalm102FollowingLatin.isHittable)
        XCTAssertEqual(
            psalm102FollowingLatin.frame.minX,
            psalm102FollowingEnglish.frame.minX,
            accuracy: 2,
            "The English should align with the Latin text after the verse number."
        )
        XCTAssertFalse(app.staticTexts["SECTION 20"].exists)
        XCTAssertFalse(app.staticTexts["[2]"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact August 29 Compline psalmody"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPrayerOptionsIncludeClericPresenceNeumeSizeAndScholaControls() {
        let app = makeApplication()
        app.launchArguments += [
            "-readerRestoration.isPresented",
            "YES",
            "-readerRestoration.day",
            "2026-08-30",
            "-readerRestoration.hour",
            "compline",
            "-readerRestoration.scrollOffset",
            "0",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["office-reader-title"].waitForExistence(timeout: 10))

        let optionsButton = app.buttons["prayer-options"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 3))
        optionsButton.tap()

        XCTAssertTrue(app.navigationBars["Prayer options"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["neume-size-slider"].exists)
        XCTAssertTrue(app.staticTexts["100%"].exists)

        let translationToggle = app.switches["translation-toggle"]
        XCTAssertTrue(translationToggle.exists)
        XCTAssertEqual(translationToggle.label, "Show English")
        XCTAssertEqual(translationToggle.value as? String, "0")
        setSwitch(translationToggle, on: true)

        let compactPsalmodyToggle = app.switches["compact-psalmody-toggle"]
        XCTAssertTrue(compactPsalmodyToggle.exists)
        XCTAssertEqual(compactPsalmodyToggle.label, "Compact psalmody")
        XCTAssertEqual(compactPsalmodyToggle.value as? String, "0")
        setSwitch(compactPsalmodyToggle, on: true)
        setSwitch(compactPsalmodyToggle, on: false)

        let clericPresence = app.buttons["priest-or-deacon-present"]
        XCTAssertTrue(clericPresence.exists)
        XCTAssertEqual(clericPresence.value as? String, "No")
        clericPresence.tap()
        XCTAssertTrue(app.buttons["Yes"].waitForExistence(timeout: 3))
        app.buttons["Yes"].tap()
        XCTAssertEqual(clericPresence.value as? String, "Yes")

        let cantorSound = app.buttons["prayer-cantor-sound"]
        XCTAssertTrue(cantorSound.exists)
        XCTAssertEqual(cantorSound.value as? String, "Organ")
        cantorSound.tap()
        XCTAssertTrue(app.buttons["Harp"].waitForExistence(timeout: 3))
        app.buttons["Harp"].tap()
        XCTAssertEqual(cantorSound.value as? String, "Harp")
        cantorSound.tap()
        XCTAssertTrue(app.buttons["Tone"].waitForExistence(timeout: 3))
        app.buttons["Tone"].tap()
        XCTAssertEqual(cantorSound.value as? String, "Tone")

        let scholaPitch = app.buttons["prayer-schola-pitch"]
        XCTAssertTrue(scholaPitch.exists)
        XCTAssertTrue(
            scholaPitch.isHittable,
            "The prayer-options sheet should be tall enough to show every option."
        )
        scholaPitch.tap()
        XCTAssertTrue(app.buttons["B♭"].waitForExistence(timeout: 3))
        app.buttons["B♭"].tap()
        XCTAssertEqual(scholaPitch.value as? String, "B♭")

        let chantRegister = app.buttons["prayer-chant-register"]
        XCTAssertTrue(chantRegister.exists)
        XCTAssertEqual(chantRegister.value as? String, "Low")
        chantRegister.tap()
        XCTAssertTrue(app.buttons["High"].waitForExistence(timeout: 3))
        app.buttons["High"].tap()
        XCTAssertEqual(chantRegister.value as? String, "High")

        let printButton = app.buttons["prayer-print-hour"]
        if !printButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(printButton.waitForExistence(timeout: 3))
        XCTAssertEqual(printButton.label, "Print this hour")

        app.buttons["prayer-options-close"].tap()
        let firstNeume = app.buttons["tour-reader-first-chant"]
        XCTAssertTrue(firstNeume.waitForExistence(timeout: 5))
        firstNeume.tap()

        let cantorPitch = app.buttons["cantor-schola-pitch"]
        XCTAssertTrue(cantorPitch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["cantor-sound"].value as? String, "Tone")
        XCTAssertEqual(cantorPitch.value as? String, "B♭")
        XCTAssertEqual(app.buttons["cantor-register"].value as? String, "High")
        XCTAssertFalse(app.steppers.matching(NSPredicate(
            format: "label BEGINSWITH 'Pitch '"
        )).firstMatch.exists)
    }

    func testPrintCurrentHourPresentsNativePrintOptions() {
        let app = makeApplication()
        app.launchArguments += [
            "-readerRestoration.isPresented",
            "YES",
            "-readerRestoration.day",
            "2026-08-30",
            "-readerRestoration.hour",
            "compline",
            "-readerRestoration.scrollOffset",
            "0",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["office-reader-title"]
                .waitForExistence(timeout: 10)
        )
        app.buttons["prayer-options"].tap()
        XCTAssertTrue(
            app.navigationBars["Prayer options"]
                .waitForExistence(timeout: 3)
        )
        setSwitch(app.switches["compact-psalmody-toggle"], on: true)

        let printButton = app.buttons["prayer-print-hour"]
        for _ in 0..<3 where !printButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(printButton.waitForExistence(timeout: 3))
        XCTAssertTrue(printButton.isEnabled)
        XCTAssertTrue(printButton.isHittable)
        printButton.tap()

        let closePrintOptions = app.buttons["Close"]
        XCTAssertTrue(closePrintOptions.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Portrait"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact Compline native print preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        closePrintOptions.tap()
        XCTAssertTrue(
            app.navigationBars["Prayer options"]
                .waitForExistence(timeout: 3)
        )
    }

    func testNonCompactPrintPreviewKeepsChantInsidePage() {
        let app = makeApplication()
        app.launchArguments += [
            "-readerRestoration.isPresented",
            "YES",
            "-readerRestoration.day",
            "2026-09-01",
            "-readerRestoration.hour",
            "compline",
            "-readerRestoration.scrollOffset",
            "0",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["office-reader-title"]
                .waitForExistence(timeout: 10)
        )
        app.buttons["prayer-options"].tap()
        XCTAssertTrue(
            app.navigationBars["Prayer options"]
                .waitForExistence(timeout: 3)
        )
        setSwitch(app.switches["compact-psalmody-toggle"], on: false)

        let printButton = app.buttons["prayer-print-hour"]
        for _ in 0..<3 where !printButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(printButton.waitForExistence(timeout: 3))
        printButton.tap()

        let closePrintOptions = app.buttons["Close"]
        XCTAssertTrue(closePrintOptions.waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Non-compact Compline native print preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        closePrintOptions.tap()
    }

    func testHomeClockCalendarAndReader() {
        let app = makeApplication(hourDisplay: "wheel")
        selectHourOnLaunch("vespers", in: app)
        app.launch()

        let dayTitle = app.staticTexts["liturgical-title"]
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let matins = app.buttons.matching(
            NSPredicate(format: "label == 'Matins'")
        ).firstMatch
        let compline = app.buttons.matching(
            NSPredicate(format: "label == 'Compline'")
        ).firstMatch
        XCTAssertTrue(matins.waitForExistence(timeout: 3))
        XCTAssertTrue(compline.waitForExistence(timeout: 3))
        let initialMatinsY = matins.frame.midY
        let initialComplineY = compline.frame.midY

        let monthDaysButton = app.buttons["home-month-days"]
        XCTAssertTrue(monthDaysButton.exists)
        XCTAssertEqual(monthDaysButton.label, "Offices for this month")
        monthDaysButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["month-days-sheet"]
                .waitForExistence(timeout: 3)
        )
        let selectedMonthDay = app.buttons.matching(
            NSPredicate(format: "value CONTAINS 'Selected'")
        ).firstMatch
        XCTAssertTrue(selectedMonthDay.waitForExistence(timeout: 3))
        app.buttons["month-days-calendar"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["office-date-picker"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["office-calendar-close"].tap()

        let initialDayTitle = dayTitle.label
        dayTitle.swipeLeft()
        let nextDayTitle = NSPredicate(
            format: "label != %@",
            initialDayTitle
        )
        expectation(
            for: nextDayTitle,
            evaluatedWith: dayTitle
        )
        waitForExpectations(timeout: 3)
        XCTAssertEqual(
            matins.frame.midY,
            initialMatinsY,
            accuracy: 1,
            "The hour list should stay pinned when the title changes."
        )
        XCTAssertEqual(
            compline.frame.midY,
            initialComplineY,
            accuracy: 1,
            "The hour list should stay pinned when the title changes."
        )

        dayTitle.swipeRight()
        let initialDayRestored = NSPredicate(
            format: "label == %@",
            initialDayTitle
        )
        expectation(
            for: initialDayRestored,
            evaluatedWith: dayTitle
        )
        waitForExpectations(timeout: 3)

        let hasSundial = app.descendants(matching: .any)[
            "canonical-hour-sundial"
        ].waitForExistence(timeout: 1)
        let hasHourWheel = app.buttons["pray-selected-hour"]
            .waitForExistence(timeout: 1)
        XCTAssertTrue(hasSundial || hasHourWheel)
        openSundialOffice("vespers", in: app)
        let readerTop = app.staticTexts["office-reader-title"]
        XCTAssertTrue(readerTop.waitForExistence(timeout: 5))
        XCTAssertTrue(readerTop.isHittable)
        XCTAssertEqual(app.webViews.count, 0)

        let firstNeume = firstRenderedNeume(in: app)
        XCTAssertTrue(firstNeume.waitForExistence(timeout: 5))

        XCTAssertFalse(app.buttons["translation-toggle"].exists)
        app.buttons["prayer-options"].tap()
        let translationToggle = app.switches["translation-toggle"]
        XCTAssertTrue(translationToggle.waitForExistence(timeout: 3))
        app.buttons["prayer-options-close"].tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Vespers reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testHomeMonthDaysSheetOpensFromRankTitleAndDate() {
        let app = makeApplication()
        app.launch()
        let homeTitle = app.staticTexts["liturgical-title"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 5))
        let initialTitle = homeTitle.label

        for identifier in [
            "liturgical-rank",
            "liturgical-title",
            "liturgical-date-detail",
        ] {
            let headerText = app.staticTexts[identifier]
            XCTAssertTrue(
                headerText.waitForExistence(timeout: 5),
                "Expected \(identifier) in the home header."
            )
            headerText.tap()

            XCTAssertTrue(
                app.descendants(matching: .any)["month-days-sheet"]
                    .waitForExistence(timeout: 3)
            )
            let selectedMonthDay = app.buttons.matching(
                NSPredicate(format: "value CONTAINS 'Selected'")
            ).firstMatch
            XCTAssertTrue(
                selectedMonthDay.waitForExistence(timeout: 3)
            )
            app.buttons["month-days-close"].tap()
        }

        app.buttons["home-month-days"].tap()
        let monthDaysList = app.descendants(matching: .any)[
            "month-days-list"
        ]
        XCTAssertTrue(monthDaysList.waitForExistence(timeout: 3))
        let visibleMonth = app.staticTexts[
            "month-days-visible-month"
        ]
        XCTAssertTrue(visibleMonth.waitForExistence(timeout: 3))
        let initialMonth = visibleMonth.label
        for _ in 0..<8
        where visibleMonth.label == initialMonth {
            monthDaysList.swipeUp()
        }
        XCTAssertNotEqual(
            visibleMonth.label,
            initialMonth
        )
        for _ in 0..<8
        where visibleMonth.label != initialMonth {
            monthDaysList.swipeDown()
        }
        XCTAssertEqual(
            visibleMonth.label,
            initialMonth
        )
        let selectedOfficeDay = app.buttons.matching(
            NSPredicate(format: "value CONTAINS 'Selected'")
        ).firstMatch
        XCTAssertTrue(
            selectedOfficeDay.waitForExistence(timeout: 3)
        )

        let calendarButton = app.buttons["month-days-calendar"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 3))
        calendarButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["office-date-picker"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["office-calendar-close"].tap()
        XCTAssertEqual(
            app.staticTexts["liturgical-title"].label,
            initialTitle
        )
    }

    func testSelectingMonthDayUpdatesHomeOffice() {
        let app = makeApplication()
        app.launch()

        let homeDate = app.staticTexts["liturgical-date-detail"]
        let homeTitle = app.staticTexts["liturgical-title"]
        XCTAssertTrue(homeDate.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 5))
        let initialDate = homeDate.label
        let initialTitle = homeTitle.label

        app.buttons["home-month-days"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["month-days-sheet"]
                .waitForExistence(timeout: 3)
        )

        let unselectedDays = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'month-day-' "
                    + "AND NOT (value CONTAINS 'Selected')"
            )
        )
        guard let targetDay = unselectedDays.allElementsBoundByIndex.first(where: {
            $0.isHittable && !$0.label.contains(initialTitle)
        }) else {
            XCTFail("Expected a visible unselected office day.")
            return
        }
        targetDay.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["month-days-sheet"]
                .waitForNonExistence(timeout: 5)
        )

        let dateChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label != %@",
                initialDate
            ),
            object: homeDate
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [dateChanged],
                timeout: 10
            ),
            .completed
        )
    }

    func testMonthDaysSheetDismissesFromDragIndicator() {
        let app = makeApplication()
        app.launch()

        app.buttons["home-month-days"].tap()
        let sheet = app.descendants(matching: .any)[
            "month-days-sheet"
        ]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))

        let dragIndicator = sheet.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)
        )
        dragIndicator.press(
            forDuration: 0.1,
            thenDragTo: dragIndicator.withOffset(
                CGVector(dx: 0, dy: 350)
            )
        )

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: sheet
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: 3),
            .completed
        )
    }

    func testCalendarDaySwipeFromEmptyHeaderSpaceAndSnapBack() {
        let app = makeApplication()
        app.launch()

        let dayTitle = app.staticTexts["liturgical-title"]
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let initialDayTitle = dayTitle.label

        let emptyHeaderY = max(
            app.frame.minY + 100,
            dayTitle.frame.minY - 40
        )
        let normalizedHeaderY =
            (emptyHeaderY - app.frame.minY) / app.frame.height
        let emptyHeaderStart = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.82,
                dy: normalizedHeaderY
            )
        )
        let emptyHeaderEnd = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.12,
                dy: normalizedHeaderY
            )
        )
        emptyHeaderStart.press(
            forDuration: 0.05,
            thenDragTo: emptyHeaderEnd
        )

        expectation(
            for: NSPredicate(
                format: "label != %@",
                initialDayTitle
            ),
            evaluatedWith: dayTitle
        )
        waitForExpectations(timeout: 3)

        let navigatedDayTitle = dayTitle.label
        let settledTitleCenterX = dayTitle.frame.midX
        let shortSwipeStart = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.55,
                dy: normalizedHeaderY
            )
        )
        let shortSwipeEnd = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.63,
                dy: normalizedHeaderY
            )
        )
        shortSwipeStart.press(
            forDuration: 0.05,
            thenDragTo: shortSwipeEnd
        )

        let springSettled = expectation(
            description: "The day title springs back to center"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            springSettled.fulfill()
        }
        wait(for: [springSettled], timeout: 2)
        XCTAssertEqual(dayTitle.label, navigatedDayTitle)
        XCTAssertEqual(
            dayTitle.frame.midX,
            settledTitleCenterX,
            accuracy: 1
        )
    }

    func testCalendarShowsTodayAndReturnsFromAnotherMonth() {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(
            app.buttons["home-month-days"].waitForExistence(timeout: 5)
        )
        app.buttons["home-month-days"].tap()
        XCTAssertTrue(
            app.buttons["month-days-calendar"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["month-days-calendar"].tap()

        let calendarToday = app.buttons["office-calendar-today"]
        XCTAssertTrue(calendarToday.waitForExistence(timeout: 3))
        if calendarToday.value as? String != "Selected, Today" {
            calendarToday.tap()
        }
        XCTAssertEqual(
            calendarToday.value as? String,
            "Selected, Today"
        )
        let visibleMonth = app.staticTexts["calendar-visible-month"]
        XCTAssertTrue(visibleMonth.exists)
        let currentMonth = visibleMonth.label
        let returnToToday = app.buttons["calendar-today"]
        XCTAssertFalse(returnToToday.exists)
        let currentMonthScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        currentMonthScreenshot.name = "Calendar current month"
        currentMonthScreenshot.lifetime = .keepAlways
        add(currentMonthScreenshot)

        app.buttons["calendar-next-month"].tap()
        expectation(
            for: NSPredicate(format: "label != %@", currentMonth),
            evaluatedWith: visibleMonth
        )
        waitForExpectations(timeout: 3)
        XCTAssertTrue(returnToToday.waitForExistence(timeout: 3))
        XCTAssertFalse(calendarToday.exists)
        let otherMonthScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        otherMonthScreenshot.name = "Calendar other month"
        otherMonthScreenshot.lifetime = .keepAlways
        add(otherMonthScreenshot)

        returnToToday.tap()
        expectation(
            for: NSPredicate(format: "label == %@", currentMonth),
            evaluatedWith: visibleMonth
        )
        waitForExpectations(timeout: 3)
        XCTAssertTrue(calendarToday.waitForExistence(timeout: 3))
        XCTAssertFalse(returnToToday.exists)
    }

    func testResetReturnsAScrubbedDayToToday() {
        let app = makeApplication()
        app.launch()

        let dayTitle = app.staticTexts["liturgical-title"]
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let todayTitle = dayTitle.label

        dayTitle.swipeLeft()
        expectation(
            for: NSPredicate(format: "label != %@", todayTitle),
            evaluatedWith: dayTitle
        )
        waitForExpectations(timeout: 3)

        app.buttons["home-settings"].tap()
        let synchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let automaticHourSelection =
            synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(
            automaticHourSelection.waitForExistence(timeout: 3)
        )
        XCTAssertFalse(automaticHourSelection.isSelected)
        automaticHourSelection.tap()

        expectation(
            for: NSPredicate(format: "label == %@", todayTitle),
            evaluatedWith: dayTitle
        )
        waitForExpectations(timeout: 3)
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: automaticHourSelection
        )
        waitForExpectations(timeout: 3)
    }

    func testHomeSettingsSwitchesHourSelectionViews() {
        let app = makeApplication(hourDisplay: nil)
        app.launch()

        let settingsButton = app.buttons["home-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertEqual(settingsButton.label, "Settings")
        settingsButton.tap()

        let settingsNavigationBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavigationBar.waitForExistence(timeout: 3))
        let hourSelectPicker =
            app.buttons["hour-display-sunDial"]
        let displayModePicker =
            app.buttons["display-mode-dynamic"]
        let synchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let manualHourSelection =
            synchronizationPicker.buttons["Manual"]
        let automaticHourSelection =
            synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(app.staticTexts["Synchronize"].exists)
        XCTAssertTrue(app.staticTexts["Display"].exists)
        let aboutButton = app.buttons["settings-about"]
        XCTAssertTrue(aboutButton.exists)
        let settingsTitle = settingsNavigationBar.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.exists)
        XCTAssertLessThan(
            aboutButton.frame.maxX,
            settingsTitle.frame.minX,
            "About should appear to the left of the Settings title."
        )
        XCTAssertTrue(hourSelectPicker.exists)
        XCTAssertTrue(displayModePicker.exists)
        XCTAssertTrue(synchronizationPicker.exists)
        XCTAssertTrue(manualHourSelection.exists)
        XCTAssertTrue(automaticHourSelection.exists)
        let appearanceDescription =
            app.staticTexts["appearance-description"]
        XCTAssertTrue(appearanceDescription.exists)
        XCTAssertTrue(appearanceDescription.isHittable)
        XCTAssertLessThanOrEqual(
            appearanceDescription.frame.maxY,
            app.windows.firstMatch.frame.maxY
        )
        XCTAssertLessThan(
            automaticHourSelection.frame.minY,
            hourSelectPicker.frame.minY
        )
        XCTAssertLessThan(
            hourSelectPicker.frame.minY,
            displayModePicker.frame.minY
        )
        XCTAssertFalse(app.buttons["Light"].exists)
        XCTAssertFalse(app.buttons["Dark"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Choose the Dial or Wheel. Both previews show the canonical hour for your current time."
            ].exists
        )

        aboutButton.tap()
        XCTAssertTrue(
            app.navigationBars["About"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["about-close"].exists)
        XCTAssertTrue(app.buttons["about-close"].isHittable)
        XCTAssertTrue(app.otherElements["hours-about-logo"].exists)
        XCTAssertTrue(
            app.otherElements["about-automatic-hour-table"].exists
        )
        XCTAssertTrue(app.staticTexts["Contact"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["about-website"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["about-contribute"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["about-email"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["about-source-code"].exists
        )
        let aboutScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        aboutScreenshot.name = "About"
        aboutScreenshot.lifetime = .keepAlways
        add(aboutScreenshot)
        app.navigationBars["About"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 3)
        )

        if !automaticHourSelection.isSelected {
            automaticHourSelection.tap()
            expectation(
                for: NSPredicate(format: "isSelected == true"),
                evaluatedWith: automaticHourSelection
            )
            waitForExpectations(timeout: 3)
        }

        hourSelectPicker.tap()
        XCTAssertTrue(
            (displayModePicker.value as? String)?
                .contains("Dial preview") == true
        )

        let automaticDescription = app.staticTexts[
            "automatic-hour-selection-description"
        ]
        XCTAssertTrue(automaticDescription.exists)
        XCTAssertTrue(automaticHourSelection.isSelected)
        XCTAssertEqual(
            automaticDescription.label,
            "Displaying the current canonical hour for your device’s current time."
        )

        manualHourSelection.tap()
        expectation(
            for: NSPredicate(
                format: "label == %@",
                "Select Automatic to synchronize and automatically keep the current hour displayed."
            ),
            evaluatedWith: automaticDescription
        )
        waitForExpectations(timeout: 3)

        automaticHourSelection.tap()
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: automaticHourSelection
        )
        waitForExpectations(timeout: 3)

        let settingsScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        settingsScreenshot.name = "Settings"
        settingsScreenshot.lifetime = .keepAlways
        add(settingsScreenshot)

        choosePickerOption(
            "Wheel",
            pickerIdentifier: "hour-select-view-picker",
            in: app
        )
        XCTAssertTrue(
            (displayModePicker.value as? String)?
                .contains("Wheel preview") == true
        )
        app.buttons["settings-close"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["canonical-hour-dial"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["canonical-hour-sundial"]
                .exists
        )

        settingsButton.tap()
        choosePickerOption(
            "Dynamic",
            pickerIdentifier: "display-mode-picker",
            in: app
        )
        app.buttons["settings-close"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["canonical-hour-dial"]
                .waitForExistence(timeout: 3)
        )
    }

    func testWheelResetReturnsToLocalTime() {
        let app = makeApplication(hourDisplay: nil)
        app.launch()

        app.buttons["home-settings"].tap()
        choosePickerOption(
            "Wheel",
            pickerIdentifier: "hour-select-view-picker",
            in: app
        )
        app.buttons["settings-close"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["canonical-hour-dial"]
                .waitForExistence(timeout: 3)
        )

        let dial = app.descendants(matching: .any)[
            "canonical-hour-dial"
        ]
        dial.swipeRight()

        app.buttons["home-settings"].tap()
        let synchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let automaticHourSelection =
            synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(
            automaticHourSelection.waitForExistence(timeout: 3)
        )
        XCTAssertFalse(automaticHourSelection.isSelected)
        automaticHourSelection.tap()

        let automaticEnabled = NSPredicate(
            format: "isSelected == true"
        )
        expectation(
            for: automaticEnabled,
            evaluatedWith: automaticHourSelection
        )
        waitForExpectations(timeout: 3)

        choosePickerOption(
            "Dial",
            pickerIdentifier: "hour-select-view-picker",
            in: app
        )
        app.buttons["settings-close"].tap()
    }

    func testDepartureSwipeAndForegroundKeepWheelAutomatic() {
        let app = makeApplication(hourDisplay: nil)
        app.launch()

        app.buttons["home-settings"].tap()
        choosePickerOption(
            "Wheel",
            pickerIdentifier: "hour-select-view-picker",
            in: app
        )
        let synchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let automaticHourSelection =
            synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(
            automaticHourSelection.waitForExistence(timeout: 3)
        )
        if !automaticHourSelection.isSelected {
            automaticHourSelection.tap()
        }
        app.buttons["settings-close"].tap()

        let dial = app.descendants(matching: .any)[
            "canonical-hour-dial"
        ]
        XCTAssertTrue(dial.waitForExistence(timeout: 3))
        dial.swipeUp()

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(dial.waitForExistence(timeout: 3))

        app.buttons["home-settings"].tap()
        let foregroundSynchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        XCTAssertTrue(
            foregroundSynchronizationPicker.buttons["Automatic"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            foregroundSynchronizationPicker.buttons["Automatic"].isSelected
        )
    }

    func testSundialTapSwipeAndReset() {
        let app = makeApplication()
        app.launch()

        let sundial = app.descendants(matching: .any)[
            "canonical-hour-sundial"
        ]
        XCTAssertTrue(sundial.waitForExistence(timeout: 5))

        let vespers = app.buttons["hour-vespers"]
        XCTAssertTrue(vespers.waitForExistence(timeout: 3))
        focusDifferentHour(than: "vespers", in: app)
        vespers.tap()

        XCTAssertFalse(app.buttons["pray-selected-hour"].exists)
        let compline = app.buttons["hour-compline"]
        XCTAssertTrue(compline.waitForExistence(timeout: 3))
        XCTAssertLessThan(
            app.windows.firstMatch.frame.maxY
                - compline.frame.midY,
            100,
            "Compline should remain pinned near the bottom edge."
        )
        let selected = NSPredicate(
            format: "value BEGINSWITH %@",
            "Selected"
        )
        expectation(
            for: selected,
            evaluatedWith: vespers
        )
        waitForExpectations(timeout: 3)

        XCTAssertFalse(
            app.segmentedControls[
                "synchronization-mode-picker"
            ].exists
        )

        let dialCenter = sundial.coordinate(
            withNormalizedOffset: CGVector(dx: 0.45, dy: 0.58)
        )
        let dialUpperArea = sundial.coordinate(
            withNormalizedOffset: CGVector(dx: 0.45, dy: 0.28)
        )
        let dialLowerArea = sundial.coordinate(
            withNormalizedOffset: CGVector(dx: 0.45, dy: 0.82)
        )
        dialCenter.press(
            forDuration: 0.08,
            thenDragTo: dialUpperArea
        )
        expectation(
            for: selected,
            evaluatedWith: compline
        )
        waitForExpectations(timeout: 3)

        dialCenter.press(
            forDuration: 0.08,
            thenDragTo: dialLowerArea
        )
        expectation(
            for: selected,
            evaluatedWith: vespers
        )
        waitForExpectations(timeout: 3)

        sundial.swipeLeft()
        expectation(
            for: selected,
            evaluatedWith: compline
        )
        waitForExpectations(timeout: 3)

        app.buttons["home-settings"].tap()
        let synchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let automaticHourSelection =
            synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(
            automaticHourSelection.waitForExistence(timeout: 3)
        )
        XCTAssertFalse(automaticHourSelection.isSelected)
        automaticHourSelection.tap()
        let automaticEnabled = NSPredicate(
            format: "isSelected == true"
        )
        expectation(
            for: automaticEnabled,
            evaluatedWith: automaticHourSelection
        )
        waitForExpectations(timeout: 3)
    }

    func testSundialRelaunchRestoresLiturgicalTitle() {
        let app = makeApplication()
        app.launchArguments += [
            "-hourSelectionView",
            "sunDial",
            "-automaticOfficeSelectionEnabled",
            "NO",
            "-manuallySelectedOfficeHour",
            "vespers",
            "-readerRestoration.isPresented",
            "NO",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["liturgical-title"]
                .waitForExistence(timeout: 5)
        )
        app.terminate()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["liturgical-title"]
                .waitForExistence(timeout: 5),
            "The current day title must be restored after reopening the sundial."
        )
        XCTAssertFalse(app.otherElements["home-load-error"].exists)
    }

    func testManualHourSurvivesForegroundAndRelaunch() {
        let app = makeApplication()
        app.launch()

        app.buttons["home-settings"].tap()
        choosePickerOption(
            "Dial",
            pickerIdentifier: "hour-select-view-picker",
            in: app
        )
        let synchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let automaticHourSelection =
            synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(
            automaticHourSelection.waitForExistence(timeout: 3)
        )
        if !automaticHourSelection.isSelected {
            automaticHourSelection.tap()
        }
        app.buttons["settings-close"].tap()

        focusDifferentHour(than: "compline", in: app)
        let compline = app.buttons["hour-compline"]
        XCTAssertTrue(compline.waitForExistence(timeout: 3))
        compline.tap()
        waitUntilSelected(compline)

        XCUIDevice.shared.press(.home)
        app.activate()
        waitUntilSelected(app.buttons["hour-compline"])

        app.terminate()
        app.launch()
        let relaunchedCompline = app.buttons["hour-compline"]
        XCTAssertTrue(relaunchedCompline.waitForExistence(timeout: 5))
        waitUntilSelected(relaunchedCompline)

        app.buttons["home-settings"].tap()
        let relaunchedSynchronizationPicker =
            app.segmentedControls["synchronization-mode-picker"]
        let relaunchedAutomaticHourSelection =
            relaunchedSynchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(
            relaunchedAutomaticHourSelection.waitForExistence(timeout: 3)
        )
        XCTAssertFalse(relaunchedAutomaticHourSelection.isSelected)

        // Restore the default so this test does not affect later UI tests.
        relaunchedAutomaticHourSelection.tap()
    }

    func testFocusedSundialHourOpensItsPrayers() {
        let app = makeApplication()
        app.launch()

        let sundial = app.descendants(matching: .any)[
            "canonical-hour-sundial"
        ]
        XCTAssertTrue(sundial.waitForExistence(timeout: 5))

        focusDifferentHour(than: "lauds", in: app)

        let lauds = app.buttons["hour-lauds"]
        XCTAssertTrue(lauds.waitForExistence(timeout: 3))
        lauds.tap()
        waitUntilSelected(lauds)
        XCTAssertFalse(app.staticTexts["office-reader-title"].exists)

        lauds.tap()
        XCTAssertTrue(
            app.staticTexts["office-reader-title"]
                .waitForExistence(timeout: 5)
        )
    }

    func testFullLiveAppTourAndStateRestoration() {
        let setupApp = makeApplication(hourDisplay: nil)
        setupApp.launch()
        XCTAssertTrue(
            setupApp.buttons["home-settings"]
                .waitForExistence(timeout: 5)
        )
        setupApp.buttons["home-settings"].tap()
        let setupDial = setupApp.buttons["hour-display-sunDial"]
        XCTAssertTrue(setupDial.waitForExistence(timeout: 3))
        if !(setupDial.value as? String ?? "").hasPrefix("Selected") {
            setupDial.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
            ).tap()
        }
        let setupSystem = setupApp.buttons["display-mode-system"]
        XCTAssertTrue(setupSystem.waitForExistence(timeout: 3))
        if !(setupSystem.value as? String ?? "").hasPrefix("Selected") {
            setupSystem.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
            ).tap()
        }
        setupApp.buttons["settings-close"].tap()
        setupApp.terminate()

        let app = pinnedRoman1960Application()
        app.launchArguments += [
            "--reset-app-tour",
            "-automaticOfficeSelectionEnabled",
            "NO",
            "-manuallySelectedOfficeHour",
            "sext",
        ]
        app.launch()

        let start = app.buttons["app-tour-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let tourCallout = app.otherElements["app-tour-overlay"]
        XCTAssertTrue(tourCallout.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Spin to Vespers"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 5)

        let hourWheel = app.descendants(matching: .any)[
            "canonical-hour-dial"
        ]
        XCTAssertTrue(hourWheel.waitForExistence(timeout: 5))
        XCTAssertFalse(
            tourCallout.frame.intersects(hourWheel.frame),
            "The floating first-step instructions must not cover the Wheel."
        )
        XCTAssertLessThanOrEqual(
            tourCallout.frame.maxY,
            hourWheel.frame.minY,
            "The first-step card must stay entirely above the Wheel."
        )
        let wheelTourScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        wheelTourScreenshot.name = "App Tour — Wheel"
        wheelTourScreenshot.lifetime = .keepAlways
        add(wheelTourScreenshot)
        hourWheel.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).press(
            forDuration: 0.2,
            thenDragTo: hourWheel.coordinate(
                withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)
            )
        )

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Pray Vespers"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 12)

        let prayVespers = app.buttons["pray-selected-hour"]
        XCTAssertTrue(prayVespers.waitForExistence(timeout: 5))
        prayVespers.tap()

        let firstNeume = app.buttons["tour-reader-first-chant"]
        XCTAssertTrue(firstNeume.waitForExistence(timeout: 5))
        waitForTourStep("Try the Cantor Guide", overlay: tourCallout)
        XCTAssertTrue(firstNeume.isHittable)
        XCTAssertLessThanOrEqual(
            firstNeume.frame.maxY,
            tourCallout.frame.minY,
            "The first-neume card must stay below the first phrase."
        )
        let firstNeumeTourScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        firstNeumeTourScreenshot.name = "App Tour — First Neume"
        firstNeumeTourScreenshot.lifetime = .keepAlways
        add(firstNeumeTourScreenshot)
        firstNeume.tap()

        let cantorPitch = app.buttons["cantor-schola-pitch"]
        XCTAssertTrue(cantorPitch.waitForExistence(timeout: 5))
        XCTAssertEqual(cantorPitch.value as? String, "A")
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Change the pitch"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 6)
        cantorPitch.tap()
        XCTAssertTrue(app.buttons["G"].waitForExistence(timeout: 3))
        app.buttons["G"].tap()
        waitForTourStep(
            "Close the Cantor Guide",
            overlay: tourCallout
        )

        let cantorClose = app.buttons["cantor-close"]
        XCTAssertTrue(cantorClose.waitForExistence(timeout: 3))
        cantorClose.tap()
        waitForTourStep("Open the contents", overlay: tourCallout)

        let contents = app.buttons["office-sections"]
        XCTAssertTrue(contents.waitForExistence(timeout: 3))
        let contentsTargetScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        contentsTargetScreenshot.name = "App Tour — Contents Target"
        contentsTargetScreenshot.lifetime = .keepAlways
        add(contentsTargetScreenshot)
        contents.tap()
        waitForTourStep("Jump to the Oratio", overlay: tourCallout)
        let oratio = app.buttons["tour-reader-oratio"]
        XCTAssertTrue(oratio.waitForExistence(timeout: 5))
        oratio.tap()
        waitForTourStep("Open prayer settings", overlay: tourCallout)

        let prayerOptions = app.buttons["prayer-options"]
        XCTAssertTrue(prayerOptions.waitForExistence(timeout: 5))
        let prayerSettingsTargetScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        prayerSettingsTargetScreenshot.name =
            "App Tour — Prayer Settings Target"
        prayerSettingsTargetScreenshot.lifetime = .keepAlways
        add(prayerSettingsTargetScreenshot)
        prayerOptions.tap()
        waitForTourStep("Show the English", overlay: tourCallout)
        let english = app.switches["translation-toggle"]
        XCTAssertTrue(english.waitForExistence(timeout: 3))
        if (english.value as? String) != "1" {
            english.coordinate(
                withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
            )
            .tap()
        }
        waitForTourStep("Close prayer settings", overlay: tourCallout)
        let prayerOptionsClose = app.buttons["prayer-options-close"]
        XCTAssertTrue(prayerOptionsClose.waitForExistence(timeout: 3))
        XCTAssertTrue(prayerOptionsClose.isHittable)
        XCTAssertLessThan(
            prayerOptionsClose.frame.midY,
            english.frame.minY,
            "Close should remain in the Prayer Options navigation bar."
        )
        let prayerOptionsCloseScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        prayerOptionsCloseScreenshot.name = "App Tour — Prayer Options Close"
        prayerOptionsCloseScreenshot.lifetime = .keepAlways
        add(prayerOptionsCloseScreenshot)
        prayerOptionsClose.tap()
        XCTAssertTrue(
            prayerOptionsClose.waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(
            tourCallout.waitForNonExistence(timeout: 0.5),
            "The tour must leave the translated Oratio unobstructed before highlighting Back."
        )
        waitForTourStep("Return home", overlay: tourCallout)

        let readerBack = app.buttons["tour-reader-back"]
        XCTAssertTrue(readerBack.waitForExistence(timeout: 5))
        XCTAssertTrue(readerBack.isHittable)
        XCTAssertFalse(
            tourCallout.frame.intersects(readerBack.frame),
            "The reader instructions must not cover Back."
        )
        let readerBackScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        readerBackScreenshot.name = "App Tour — Reader Back"
        readerBackScreenshot.lifetime = .keepAlways
        add(readerBackScreenshot)
        readerBack.tap()

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Open the calendar"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 8)

        let calendarButton = app.buttons["home-month-days"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 5))
        calendarButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["month-days-sheet"]
                .waitForExistence(timeout: 5)
        )

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Explore the month list"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 5)

        let monthLabel = app.staticTexts["month-days-visible-month"]
        XCTAssertTrue(monthLabel.waitForExistence(timeout: 3))
        let initialMonth = monthLabel.label
        let monthList = app.descendants(matching: .any)["month-days-list"]
        XCTAssertTrue(monthList.waitForExistence(timeout: 3))
        let monthSheet = app.descendants(matching: .any)["month-days-sheet"]
        XCTAssertLessThanOrEqual(
            tourCallout.frame.maxY,
            monthSheet.frame.minY,
            "The month-list instructions should sit above the calendar sheet."
        )
        XCTAssertFalse(
            tourCallout.frame.intersects(monthList.frame),
            "The month-list instructions must not cover the scrollable list."
        )
        let calendarListTourScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        calendarListTourScreenshot.name = "App Tour — Month List"
        calendarListTourScreenshot.lifetime = .keepAlways
        add(calendarListTourScreenshot)
        for _ in 0..<10 where monthLabel.label == initialMonth {
            monthList.swipeUp()
        }
        XCTAssertNotEqual(monthLabel.label, initialMonth)
        waitForTourStep("Open the calendar grid", overlay: tourCallout)

        let calendarGrid = app.buttons["month-days-calendar"]
        XCTAssertTrue(calendarGrid.waitForExistence(timeout: 5))
        calendarGrid.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["office-date-picker"]
                .waitForExistence(timeout: 5)
        )
        waitForTourStep("Return to Hours", overlay: tourCallout)
        let calendarClose = app.buttons["office-calendar-close"]
        XCTAssertTrue(calendarClose.waitForExistence(timeout: 3))
        let calendarSheet = app.descendants(matching: .any)[
            "month-days-sheet"
        ]
        let compactCalendarScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        compactCalendarScreenshot.name =
            "App Tour — Calendar Close — Compact"
        compactCalendarScreenshot.lifetime = .keepAlways
        add(compactCalendarScreenshot)
        let mediumSheetMinY = calendarSheet.frame.minY
        calendarSheet.swipeUp()
        XCTAssertLessThan(calendarSheet.frame.minY, mediumSheetMinY)
        XCTAssertTrue(
            calendarClose.isHittable,
            "Calendar close should remain targeted at the large detent."
        )
        let calendarCloseScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        calendarCloseScreenshot.name =
            "App Tour — Calendar Close — Large"
        calendarCloseScreenshot.lifetime = .keepAlways
        add(calendarCloseScreenshot)
        calendarClose.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["month-days-sheet"]
                .waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Move between days"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 5)
        calendarButton.swipeLeft()

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Search the Office"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 8)

        let search = app.buttons["home-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 3),
            "The guided Search step should focus the native search field."
        )
        let searchTourBar = app.otherElements["app-tour-overlay"]
        XCTAssertTrue(searchTourBar.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(
            searchTourBar.frame.maxY,
            app.keyboards.firstMatch.frame.minY + 1,
            "Tour instructions should remain above the keyboard."
        )
        searchField.typeText("Salve Regina\n")
        waitForTourStep("Filter to chants", overlay: tourCallout, timeout: 12)

        let chants = app.buttons["search-category-chants"]
        XCTAssertTrue(chants.waitForExistence(timeout: 10))
        chants.tap()
        waitForTourStep("Open Salve Regina", overlay: tourCallout)

        let salveRegina = app.descendants(matching: .any)[
            "search-result-0"
        ]
        XCTAssertTrue(salveRegina.waitForExistence(timeout: 8))
        salveRegina.tap()
        waitForTourStep("Choose a chant setting", overlay: tourCallout)

        let chantSettings = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "search-chant-setting-"
            )
        )
        let firstSetting = chantSettings.element(boundBy: 0)
        XCTAssertTrue(firstSetting.waitForExistence(timeout: 8))
        firstSetting.tap()
        XCTAssertTrue(
            tourCallout.waitForNonExistence(timeout: 0.5),
            "The overlay should clear briefly so the chant can be viewed."
        )
        waitForTourStep("Explore another setting", overlay: tourCallout)
        let chantBack = app.buttons["tour-search-chant-back"]
        XCTAssertTrue(chantBack.waitForExistence(timeout: 8))
        XCTAssertFalse(
            tourCallout.frame.intersects(chantBack.frame),
            "The chant instructions must not cover Back."
        )
        let chantBackScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        chantBackScreenshot.name = "App Tour — Chant Back"
        chantBackScreenshot.lifetime = .keepAlways
        add(chantBackScreenshot)
        chantBack.tap()
        waitForTourStep("Choose another setting", overlay: tourCallout)

        let secondSetting = chantSettings.element(boundBy: 1)
        XCTAssertTrue(secondSetting.waitForExistence(timeout: 8))
        secondSetting.tap()
        waitForTourStep("Return to the result", overlay: tourCallout)
        XCTAssertTrue(chantBack.waitForExistence(timeout: 8))
        chantBack.tap()
        waitForTourStep("Return to Search", overlay: tourCallout)

        let detailBack = app.buttons["tour-search-detail-back"]
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5))
        XCTAssertFalse(
            tourCallout.frame.intersects(detailBack.frame),
            "The result instructions must not cover Back."
        )
        let detailBackScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        detailBackScreenshot.name = "App Tour — Detail Back"
        detailBackScreenshot.lifetime = .keepAlways
        add(detailBackScreenshot)
        detailBack.tap()
        waitForTourStep("Return home", overlay: tourCallout)

        let searchClose = app.buttons["prayer-search-close"]
        XCTAssertTrue(searchClose.waitForExistence(timeout: 3))
        let searchTourScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        searchTourScreenshot.name = "App Tour — Search"
        searchTourScreenshot.lifetime = .keepAlways
        add(searchTourScreenshot)
        searchClose.tap()

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Explore display options"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 12)

        let settings = app.buttons["home-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        waitForTourStep("Change the Hour display", overlay: tourCallout)
        let dial = app.buttons["hour-display-sunDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 3))
        dial.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
        ).tap()
        expectation(
            for: NSPredicate(format: "value BEGINSWITH %@", "Selected"),
            evaluatedWith: dial
        )
        waitForExpectations(timeout: 5)
        waitForTourStep("Change the appearance", overlay: tourCallout)
        let system = app.buttons["display-mode-system"]
        XCTAssertTrue(system.waitForExistence(timeout: 3))
        system.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
        ).tap()
        expectation(
            for: NSPredicate(format: "value BEGINSWITH %@", "Selected"),
            evaluatedWith: system
        )
        waitForExpectations(timeout: 5)
        waitForTourStep("Return home", overlay: tourCallout)
        app.buttons["settings-close"].tap()

        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        waitForTourStep("Return to Settings", overlay: tourCallout)
        settings.tap()
        waitForTourStep("Restore the Wheel", overlay: tourCallout)
        let wheel = app.buttons["hour-display-wheel"]
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        wheel.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
        ).tap()
        expectation(
            for: NSPredicate(format: "value BEGINSWITH %@", "Selected"),
            evaluatedWith: wheel
        )
        waitForExpectations(timeout: 5)
        waitForTourStep(
            "Restore Dynamic appearance",
            overlay: tourCallout
        )
        let dynamic = app.buttons["display-mode-dynamic"]
        XCTAssertTrue(dynamic.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: dynamic
        )
        waitForExpectations(timeout: 5)
        dynamic.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        expectation(
            for: NSPredicate(format: "value BEGINSWITH %@", "Selected"),
            evaluatedWith: dynamic
        )
        waitForExpectations(timeout: 5)
        waitForTourStep(
            "Resume Automatic tracking",
            overlay: tourCallout
        )
        let synchronizationPicker = app.segmentedControls[
            "synchronization-mode-picker"
        ]
        let automatic = synchronizationPicker.buttons["Automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        automatic.tap()
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: automatic
        )
        waitForExpectations(timeout: 5)
        waitForTourStep("Open About", overlay: tourCallout)
        let about = app.buttons["settings-about"]
        XCTAssertTrue(about.waitForExistence(timeout: 3))
        let settingsTitle = app.navigationBars["Settings"]
            .staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.exists)
        XCTAssertLessThan(
            about.frame.maxX,
            settingsTitle.frame.minX,
            "The tour should target About left of the Settings title."
        )
        XCTAssertFalse(
            tourCallout.frame.intersects(about.frame),
            "The tour instructions must not cover the About button."
        )
        let aboutTargetScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        aboutTargetScreenshot.name = "App Tour — About Target"
        aboutTargetScreenshot.lifetime = .keepAlways
        add(aboutTargetScreenshot)
        about.tap()
        XCTAssertTrue(
            app.navigationBars["About"].waitForExistence(timeout: 5)
        )
        waitForTourStep("Tour complete", overlay: tourCallout)

        let finish = app.buttons["app-tour-finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        let finishTourScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        finishTourScreenshot.name = "App Tour — Finish"
        finishTourScreenshot.lifetime = .keepAlways
        add(finishTourScreenshot)
        finish.tap()

        XCTAssertTrue(
            app.otherElements["app-tour-overlay"]
                .waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(app.navigationBars["About"].exists)
        app.buttons["about-close"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let completedSynchronizationPicker = app.segmentedControls[
            "synchronization-mode-picker"
        ]
        XCTAssertTrue(
            completedSynchronizationPicker.buttons["Automatic"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            completedSynchronizationPicker.buttons["Automatic"].isSelected
        )
        XCTAssertTrue(
            (app.buttons["hour-display-wheel"].value as? String ?? "")
                .hasPrefix("Selected")
        )
        XCTAssertTrue(
            (app.buttons["display-mode-dynamic"].value as? String ?? "")
                .hasPrefix("Selected")
        )
    }

    func testTourAdvancesWhenVespersIsAlreadySelected() {
        let app = pinnedRoman1960Application()
        app.launchArguments += [
            "--reset-app-tour",
            "-hourSelectionView",
            "wheel",
            "-automaticOfficeSelectionEnabled",
            "NO",
            "-manuallySelectedOfficeHour",
            "vespers",
        ]
        app.launch()

        let start = app.buttons["app-tour-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let tourCallout = app.otherElements["app-tour-overlay"]
        XCTAssertTrue(tourCallout.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Spin to Prime"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 5)

        let selectedVespers = app.buttons["hour-vespers"]
        XCTAssertTrue(selectedVespers.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (selectedVespers.value as? String ?? "")
                .hasPrefix("Selected")
        )

        let wheel = app.descendants(matching: .any)[
            "canonical-hour-dial"
        ]
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        spinWheel(to: "prime", wheel: wheel, in: app)

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Spin back to Vespers"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 8)

        spinWheel(to: "vespers", wheel: wheel, in: app)

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Pray Vespers"
            ),
            evaluatedWith: tourCallout
        )
        waitForExpectations(timeout: 8)
        app.buttons["app-tour-skip"].tap()
    }

    func testAboutReplayDismissesSettingsAndStartsFromHome() {
        let app = makeApplication(hourDisplay: "wheel")
        // A fixed starting hour, so that the wheel reaches Vespers whatever
        // the time of day.
        app.launchArguments += [
            "-automaticOfficeSelectionEnabled", "NO",
            "-manuallySelectedOfficeHour", "sext",
        ]
        app.launch()

        XCTAssertTrue(
            app.buttons["home-settings"].waitForExistence(timeout: 5)
        )
        app.buttons["home-settings"].tap()
        app.buttons["settings-about"].tap()
        let replay = app.buttons["about-app-tour"]
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        replay.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["canonical-hour-dial"]
                .waitForExistence(timeout: 5)
        )
        let replayOverlay = app.otherElements["app-tour-overlay"]
        XCTAssertTrue(replayOverlay.waitForExistence(timeout: 3))
        let replayWheel = app.descendants(matching: .any)[
            "canonical-hour-dial"
        ]
        spinWheel(to: "vespers", wheel: replayWheel, in: app)
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Pray Vespers"
            ),
            evaluatedWith: replayOverlay
        )
        waitForExpectations(timeout: 12)
        app.buttons["app-tour-skip"].tap()
    }

    func testAboutReplayRemainsInteractiveWithoutRelaunchingApp() {
        let app = pinnedRoman1960Application()
        app.launchArguments += [
            "--reset-app-tour",
            "-hourSelectionView",
            "wheel",
            "-automaticOfficeSelectionEnabled",
            "NO",
            "-manuallySelectedOfficeHour",
            "sext",
        ]
        app.launch()

        let start = app.buttons["app-tour-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let overlay = app.otherElements["app-tour-overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        app.buttons["app-tour-skip"].tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 5))

        app.buttons["home-settings"].tap()
        app.buttons["settings-about"].tap()
        let replay = app.buttons["about-app-tour"]
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        replay.tap()

        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        let wheel = app.descendants(matching: .any)[
            "canonical-hour-dial"
        ]
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        spinWheel(to: "vespers", wheel: wheel, in: app)

        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Pray Vespers"
            ),
            evaluatedWith: overlay
        )
        waitForExpectations(timeout: 12)
        app.buttons["app-tour-skip"].tap()
    }

    private func waitForTourStep(
        _ title: String,
        overlay: XCUIElement,
        timeout: TimeInterval = 8
    ) {
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                title
            ),
            evaluatedWith: overlay
        )
        waitForExpectations(timeout: timeout)
    }

    /// Most cases open an Hour from the sundial; the fresh install's default
    /// is the wheel. A case that switches the display in Settings passes nil,
    /// since a launch argument would override its choice.
    private func makeApplication(hourDisplay: String? = "sunDial") -> XCUIApplication {
        let app = pinnedRoman1960Application()
        if let hourDisplay {
            app.launchArguments += ["-hourSelectionView", hourDisplay]
        }
        app.launchArguments += [
            "--suppress-app-tour",
            "-readerRestoration.isPresented",
            "NO",
        ]
        return app
    }

    /// The edition is a persisted setting, and a test that switches it
    /// (OfficeTraditionUITests) would otherwise leave later tests reading
    /// Roman 1954. The launch argument overrides the stored choice.
    private func pinnedRoman1960Application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-officeTradition", "roman1960"]
        return app
    }

    private func firstRenderedNeume(
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: """
                identifier BEGINSWITH %@ OR identifier BEGINSWITH %@
                """,
                "reference-",
                "office-section-"
            )
        ).firstMatch
    }

    private func selectHourOnLaunch(
        _ hour: String,
        in app: XCUIApplication
    ) {
        app.launchArguments += [
            "-automaticOfficeSelectionEnabled",
            "NO",
            "-manuallySelectedOfficeHour",
            hour,
        ]
    }

    private func openSundialOffice(
        _ hour: String,
        in app: XCUIApplication
    ) {
        let dialButton = app.buttons["hour-\(hour)"]
        let sundial = app.descendants(matching: .any)[
            "canonical-hour-sundial"
        ]
        // Allow the home screen to finish launching before choosing a path.
        if sundial.waitForExistence(timeout: 5),
           dialButton.waitForExistence(timeout: 1) {
            if !isSelected(dialButton) {
                dialButton.tap()
                waitUntilSelected(dialButton)
            }
            dialButton.tap()
            return
        }

        let prayButton = app.buttons["pray-selected-hour"]
        if prayButton.waitForExistence(timeout: 1),
           dialButton.waitForExistence(timeout: 1) {
            prayButton.tap()
            return
        }

        let listButton = app.buttons["hour-option-\(hour)"]
        XCTAssertTrue(listButton.waitForExistence(timeout: 5))
        for _ in 0..<6 where !listButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(
            listButton.isHittable,
            "Expected the \(hour) row to become visible in the hour list."
        )
        if !isSelected(listButton) {
            listButton.tap()
            waitUntilSelected(listButton)
        }
        XCTAssertTrue(prayButton.waitForExistence(timeout: 3))
        prayButton.tap()
    }

    private func focusDifferentHour(
        than excludedHour: String,
        in app: XCUIApplication
    ) {
        let alternateHours = [
            "matins",
            "lauds",
            "prime",
            "terce",
            "sext",
            "none",
            "vespers",
            "compline",
        ].filter { $0 != excludedHour }

        guard let button = alternateHours
            .flatMap({ hour in
                [
                    app.buttons["hour-\(hour)"],
                    app.buttons["hour-option-\(hour)"]
                ]
            })
            .first(where: {
                $0.waitForExistence(timeout: 1)
                    && !isSelected($0)
            }) else {
            XCTFail("Expected an unfocused alternate sundial hour.")
            return
        }

        button.tap()
        waitUntilSelected(button)
    }

    private func spinWheel(
        to hour: String,
        wheel: XCUIElement,
        in app: XCUIApplication
    ) {
        let selectedHour = app.buttons["hour-\(hour)"]
        for _ in 0..<12 where !selectedHour.exists {
            wheel.coordinate(
                withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)
            ).press(
                forDuration: 0.7,
                thenDragTo: wheel.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5)
                )
            )
            _ = selectedHour.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(
            selectedHour.exists,
            "Expected the Wheel to settle on \(hour)."
        )
    }

    private func choosePickerOption(
        _ option: String,
        pickerIdentifier: String,
        in app: XCUIApplication
    ) {
        let optionIdentifier: String
        switch (pickerIdentifier, option) {
        case ("hour-select-view-picker", "Dial"):
            optionIdentifier = "hour-display-sunDial"
        case ("hour-select-view-picker", "Wheel"):
            optionIdentifier = "hour-display-wheel"
        case ("display-mode-picker", "Dynamic"):
            optionIdentifier = "display-mode-dynamic"
        case ("display-mode-picker", "System"):
            optionIdentifier = "display-mode-system"
        default:
            XCTFail(
                "Unknown settings option \(option) for \(pickerIdentifier)"
            )
            return
        }

        let optionButton = app.buttons[optionIdentifier]
        XCTAssertTrue(optionButton.waitForExistence(timeout: 3))
        optionButton.tap()
    }

    private func waitUntilSelected(_ button: XCUIElement) {
        let selected = NSPredicate(
            format: "value BEGINSWITH %@",
            "Selected"
        )
        expectation(for: selected, evaluatedWith: button)
        waitForExpectations(timeout: 3)
    }

    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        let expectedValue = on ? "1" : "0"
        guard toggle.value as? String != expectedValue else { return }

        toggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        expectation(
            for: NSPredicate(format: "value == %@", expectedValue),
            evaluatedWith: toggle
        )
        waitForExpectations(timeout: 3)
    }

    private func isSelected(_ button: XCUIElement) -> Bool {
        (button.value as? String)?.hasPrefix("Selected") == true
    }
}
