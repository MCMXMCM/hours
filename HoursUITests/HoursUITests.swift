import XCTest

@MainActor
final class HoursUITests: XCTestCase {
    func testSelectablePrayerTextInteraction() {
        let app = XCUIApplication()
        app.launch()

        openSundialOffice("prime", in: app)
        XCTAssertTrue(
            app.staticTexts["office-reader-title"].waitForExistence(timeout: 5)
        )

        let paragraph = app.staticTexts
            .matching(identifier: "selectable-prayer-text")
            .firstMatch
        for _ in 0..<12 where !paragraph.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(paragraph.isHittable)

        paragraph.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        .press(forDuration: 1)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Selectable prayer text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPrayerAlwaysStartsAtTop() {
        let app = XCUIApplication()
        app.launch()

        openSundialOffice("lauds", in: app)

        let readerTop = app.staticTexts["development-corpus-banner"]
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
        let app = XCUIApplication()
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
        let doneButton = app.buttons["office-sections-done"]
        XCTAssertTrue(doneButton.exists)

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
        doneButton.tap()
        XCTAssertTrue(
            sheetNavigationBar.waitForNonExistence(timeout: 3)
        )
    }

    func testSelectedHourShowsBundledNotationImmediately() {
        let app = XCUIApplication()
        app.launch()

        openSundialOffice("lauds", in: app)
        XCTAssertTrue(app.staticTexts["office-reader-title"].waitForExistence(timeout: 5))

        let firstImportedNeume = firstRenderedNeume(in: app)
        XCTAssertTrue(
            firstImportedNeume.waitForExistence(timeout: 10),
            "The selected hour should render its first imported chant before the office text."
        )
    }

    func testCompactTercePsalmHidesImporterLabelsAndScoredVerseDuplicate() {
        let app = XCUIApplication()
        app.launch()

        let sundial = app.descendants(matching: .any)[
            "canonical-hour-sundial"
        ]
        XCTAssertTrue(sundial.waitForExistence(timeout: 5))
        let terce = app.buttons["hour-terce"]
        XCTAssertTrue(terce.waitForExistence(timeout: 3))
        openSundialOffice("terce", in: app)
        XCTAssertTrue(app.staticTexts["office-reader-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["translation-toggle"].exists)
        app.buttons["prayer-options"].tap()
        let translationToggle = app.switches["translation-toggle"]
        XCTAssertTrue(translationToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(translationToggle.value as? String, "0")
        translationToggle.tap()
        XCTAssertEqual(translationToggle.value as? String, "1")
        app.buttons["Done"].tap()

        let secondPsalmHeading = app.staticTexts["Psalmus 79 (9,20)"]
        for _ in 0..<12 where !secondPsalmHeading.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(secondPsalmHeading.isHittable)

        let secondVerse = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Dux itíneris fuísti")
        ).firstMatch
        for _ in 0..<6 where !secondVerse.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(secondVerse.isHittable)
        XCTAssertFalse(app.staticTexts["SECTION 4"].exists)
        XCTAssertFalse(app.staticTexts["[2]"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "79:9 ")
            ).firstMatch.exists
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact Terce psalm"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPrayerOptionsIncludeClericPresenceNeumeSizeAndScholaControls() {
        let app = XCUIApplication()
        app.launch()

        openSundialOffice("lauds", in: app)
        XCTAssertTrue(app.staticTexts["office-reader-title"].waitForExistence(timeout: 5))

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
        translationToggle.tap()
        XCTAssertEqual(translationToggle.value as? String, "1")

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

        app.buttons["Done"].tap()
        let firstNeume = firstRenderedNeume(in: app)
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

    func testHomeClockCalendarAndReader() {
        let app = XCUIApplication()
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
        app.buttons["Done"].tap()

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

        let sundial = app.descendants(matching: .any)[
            "canonical-hour-sundial"
        ]
        XCTAssertTrue(sundial.waitForExistence(timeout: 3))

        let vespers = app.buttons["hour-vespers"]
        XCTAssertTrue(vespers.waitForExistence(timeout: 3))
        XCTAssertTrue(vespers.isHittable)
        focusDifferentHour(than: "vespers", in: app)
        vespers.tap()
        XCTAssertTrue(
            (vespers.value as? String)?.hasPrefix("Selected") == true
        )
        vespers.tap()
        let readerTop = app.staticTexts["development-corpus-banner"]
        XCTAssertTrue(readerTop.waitForExistence(timeout: 5))
        XCTAssertTrue(readerTop.isHittable)
        XCTAssertEqual(app.webViews.count, 0)

        let firstNeume = firstRenderedNeume(in: app)
        XCTAssertTrue(firstNeume.waitForExistence(timeout: 5))
        firstNeume.tap()
        XCTAssertTrue(app.buttons["cantor-play"].waitForExistence(timeout: 5))

        let cantorGuide = app.staticTexts["Cantor guide"].firstMatch
        XCTAssertTrue(cantorGuide.waitForExistence(timeout: 5))
        let closeCantorGuide = app.buttons["cantor-close"]
        XCTAssertTrue(closeCantorGuide.isHittable)
        closeCantorGuide.tap()
        XCTAssertTrue(cantorGuide.waitForNonExistence(timeout: 5))

        XCTAssertFalse(app.buttons["translation-toggle"].exists)
        app.buttons["prayer-options"].tap()
        let translationToggle = app.switches["translation-toggle"]
        XCTAssertTrue(translationToggle.waitForExistence(timeout: 3))
        translationToggle.tap()
        XCTAssertEqual(translationToggle.value as? String, "1")
        app.buttons["Done"].tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Vespers reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testHomeMonthDaysSheetOpensFromRankTitleAndDate() {
        let app = XCUIApplication()
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
            app.buttons["month-days-done"].tap()
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
        app.buttons["Done"].tap()
        XCTAssertEqual(
            app.staticTexts["liturgical-title"].label,
            initialTitle
        )
    }

    func testSelectingMonthDayUpdatesHomeOffice() {
        let app = XCUIApplication()
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
        let targetDay = unselectedDays.allElementsBoundByIndex.first {
            $0.isHittable && !$0.label.contains(initialTitle)
        }
        XCTAssertNotNil(targetDay)
        targetDay?.tap()

        let dateChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label != %@",
                initialDate
            ),
            object: homeDate
        )
        let titleChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label != %@",
                initialTitle
            ),
            object: homeTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [dateChanged, titleChanged],
                timeout: 5
            ),
            .completed
        )
    }

    func testMonthDaysSheetDismissesFromDragIndicator() {
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["home-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertEqual(settingsButton.label, "Settings")
        settingsButton.tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 3)
        )
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
        XCTAssertTrue(app.buttons["settings-about"].exists)
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

        app.buttons["settings-about"].tap()
        XCTAssertTrue(
            app.navigationBars["About"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["about-done"].exists)
        XCTAssertTrue(app.buttons["about-done"].isHittable)
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
        app.buttons["Done"].tap()
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
        app.buttons["Done"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["canonical-hour-dial"]
                .waitForExistence(timeout: 3)
        )
    }

    func testWheelResetReturnsToLocalTime() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["home-settings"].tap()
        choosePickerOption(
            "Wheel",
            pickerIdentifier: "hour-select-view-picker",
            in: app
        )
        app.buttons["Done"].tap()

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
        app.buttons["Done"].tap()
    }

    func testDepartureSwipeAndForegroundKeepWheelAutomatic() {
        let app = XCUIApplication()
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
        app.buttons["Done"].tap()

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
        let app = XCUIApplication()
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

    func testManualHourSurvivesForegroundAndRelaunch() {
        let app = XCUIApplication()
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
        app.buttons["Done"].tap()

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
        let app = XCUIApplication()
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

    private func openSundialOffice(
        _ hour: String,
        in app: XCUIApplication
    ) {
        let button = app.buttons["hour-\(hour)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))

        if !isSelected(button) {
            button.tap()
            waitUntilSelected(button)
        }

        button.tap()
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
            .map({ app.buttons["hour-\($0)"] })
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

    private func isSelected(_ button: XCUIElement) -> Bool {
        (button.value as? String)?.hasPrefix("Selected") == true
    }
}
