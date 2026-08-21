@testable import Hours
import HoursCore
import XCTest

@MainActor
final class AppTourCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var standardSuiteName = ""
    nonisolated(unsafe) private var appearanceSuiteName = ""
    nonisolated(unsafe) private var standardDefaults: UserDefaults!
    nonisolated(unsafe) private var appearanceDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        standardSuiteName = "AppTour.standard.\(UUID().uuidString)"
        appearanceSuiteName = "AppTour.appearance.\(UUID().uuidString)"
        standardDefaults = try XCTUnwrap(
            UserDefaults(suiteName: standardSuiteName)
        )
        appearanceDefaults = try XCTUnwrap(
            UserDefaults(suiteName: appearanceSuiteName)
        )
    }

    override func tearDown() {
        standardDefaults.removePersistentDomain(
            forName: standardSuiteName
        )
        appearanceDefaults.removePersistentDomain(
            forName: appearanceSuiteName
        )
        standardDefaults = nil
        appearanceDefaults = nil
        super.tearDown()
    }

    func testFreshAndExistingInstallationsReceiveOfferOnce() {
        for hasUnrelatedExistingPreference in [false, true] {
            standardDefaults.removeObject(
                forKey: AppTourPersistence.initialOfferSeenKey
            )
            if hasUnrelatedExistingPreference {
                standardDefaults.set(true, forKey: "existing-user")
            }
            let tour = makeTour()

            tour.launchAnimationCompleted()
            XCTAssertTrue(tour.isWelcomePresented)
            tour.requestWelcomeSkip()
            XCTAssertTrue(
                standardDefaults.bool(
                    forKey: AppTourPersistence.initialOfferSeenKey
                )
            )

            let relaunchedTour = makeTour()
            relaunchedTour.launchAnimationCompleted()
            XCTAssertFalse(relaunchedTour.isWelcomePresented)
        }
    }

    func testEveryWelcomeDismissalPathMarksOfferSeen() {
        let actions: [(AppTourCoordinator) -> Void] = [
            { $0.requestWelcomeStart() },
            { $0.requestWelcomeSkip() },
            { $0.requestWelcomeClose() },
        ]

        for action in actions {
            standardDefaults.removeObject(
                forKey: AppTourPersistence.initialOfferSeenKey
            )
            let tour = makeTour()
            tour.launchAnimationCompleted()
            action(tour)
            XCTAssertTrue(
                standardDefaults.bool(
                    forKey: AppTourPersistence.initialOfferSeenKey
                )
            )
        }
    }

    func testBeginningTourUsesPredictableDisplayDefaults() {
        let tour = makeTour()

        tour.begin(
            snapshot: snapshot(
                day: LocalDay(year: 2026, month: 8, day: 20),
                hourDisplay: .sunDial,
                appearance: .system
            )
        )

        XCTAssertEqual(
            standardDefaults.string(
                forKey: AppTourPersistence.hourDisplayKey
            ),
            HourSelectionViewMode.wheel.rawValue
        )
        XCTAssertEqual(
            appearanceDefaults.string(
                forKey: HoursSharedPreferences.appearanceModeKey
            ),
            AppDisplayMode.dynamic.rawValue
        )
    }

    func testBeginningTourTemporarilyHidesEnglish() {
        standardDefaults.set(true, forKey: AppModel.showsEnglishKey)
        let model = AppModel(userDefaults: standardDefaults)
        let tour = makeTour()

        tour.begin(model: model)

        XCTAssertFalse(model.showsEnglish)
        let recoveryData = standardDefaults.data(
            forKey: AppTourPersistence.recoverySnapshotKey
        )
        let recovery = recoveryData.flatMap {
            try? JSONDecoder().decode(AppTourSnapshot.self, from: $0)
        }
        XCTAssertEqual(recovery?.showsEnglish, true)
    }

    func testInvalidRecoverySnapshotIsDiscarded() {
        standardDefaults.set(
            Data("not-json".utf8),
            forKey: AppTourPersistence.recoverySnapshotKey
        )

        XCTAssertNil(
            AppTourPersistence.recoverInterruptedSnapshot(
                standardDefaults: standardDefaults,
                appearanceDefaults: appearanceDefaults
            )
        )
        XCTAssertNil(
            standardDefaults.data(
                forKey: AppTourPersistence.recoverySnapshotKey
            )
        )
    }

    func testTourBrieflyClearsOverlayBetweenCompletedActions() async throws {
        let tour = AppTourCoordinator(
            standardDefaults: standardDefaults,
            appearanceDefaults: appearanceDefaults,
            cantorGuideAppreciationDelay: .zero,
            transitionDelayOverride: .milliseconds(50)
        )
        tour.begin(
            snapshot: snapshot(
                day: LocalDay(year: 2026, month: 8, day: 20)
            )
        )

        XCTAssertTrue(tour.presentsOverlay)
        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))

        XCTAssertTrue(tour.isTransitioning)
        XCTAssertFalse(tour.presentsOverlay)
        XCTAssertEqual(tour.step, .chooseHour)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(tour.isTransitioning)
        XCTAssertTrue(tour.presentsOverlay)
        XCTAssertEqual(tour.step, .prayVespers)
    }

    func testOnlyRevealStepsPauseBeforeIntroducingNextTarget() {
        XCTAssertEqual(
            AppTourStep.chooseHour.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertEqual(
            AppTourStep.prayVespers.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertEqual(
            AppTourStep.returnFromFirstChant.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertGreaterThan(
            AppTourStep.chooseOratio.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertGreaterThan(
            AppTourStep.chooseFirstChantSetting.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertEqual(
            AppTourStep.enableEnglish.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertEqual(
            AppTourStep.swipeDay.revealDelayAfterCompletion,
            .zero
        )
        XCTAssertEqual(
            AppTourStep.closeReaderOptions.revealDelayAfterCompletion,
            .seconds(2)
        )
    }

    func testCoordinatorRejectsUnrelatedAndDuplicateEvents() {
        let tour = makeTour()
        let original = LocalDay(year: 2026, month: 8, day: 20)
        tour.begin(snapshot: snapshot(day: original))

        tour.receive(.searchOpened)
        XCTAssertEqual(tour.step, .chooseHour)
        tour.receive(.hourSelected(.lauds))
        tour.receive(.officeLoaded(.lauds))
        XCTAssertEqual(tour.step, .chooseHour)
        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))
        XCTAssertEqual(tour.step, .prayVespers)
        tour.receive(.calendarOpened)
        XCTAssertEqual(tour.step, .prayVespers)
        advanceReaderTour(tour)
        XCTAssertEqual(tour.step, .openCalendar)
        tour.receive(.calendarOpened)
        XCTAssertEqual(tour.step, .scrollCalendarMonth)
        tour.receive(.calendarOpened)
        XCTAssertEqual(tour.step, .scrollCalendarMonth)
        tour.receive(.calendarGridOpened)
        XCTAssertEqual(tour.step, .scrollCalendarMonth)
    }

    func testVespersStartSpinsToPrimeThenBackToVespers() {
        let tour = makeTour()
        tour.begin(
            snapshot: snapshot(
                day: LocalDay(year: 2026, month: 8, day: 20),
                hour: .vespers
            )
        )

        XCTAssertEqual(tour.step, .chooseHour)
        XCTAssertEqual(tour.requestedHour, .prime)
        XCTAssertEqual(tour.title, "Spin to Prime")
        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))
        XCTAssertEqual(tour.requestedHour, .prime)

        tour.receive(.hourSelected(.prime))
        tour.receive(.officeLoaded(.prime))
        XCTAssertEqual(tour.step, .chooseHour)
        XCTAssertEqual(tour.requestedHour, .vespers)
        XCTAssertEqual(tour.title, "Spin back to Vespers")

        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))
        XCTAssertEqual(tour.step, .prayVespers)
    }

    func testCompleteGuidedTransitionSequence() {
        let tour = makeTour()
        let original = LocalDay(year: 2026, month: 8, day: 20)
        tour.begin(snapshot: snapshot(day: original))

        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))
        advanceReaderTour(tour)
        tour.receive(.calendarOpened)
        tour.receive(.calendarMonthAdvanced)
        tour.receive(.calendarGridOpened)
        tour.receive(
            .calendarClosed(
                canSwipePrevious: true,
                canSwipeNext: true
            )
        )
        XCTAssertEqual(tour.requiredDaySwipeOffset, 1)
        tour.receive(.daySwiped(-1))
        XCTAssertEqual(tour.step, .swipeDay)
        tour.receive(.daySwiped(1))
        XCTAssertEqual(tour.step, .openSearch)

        tour.receive(.searchOpened)
        tour.receive(
            .searchResultsLoaded(query: "Salve Regina", count: 4)
        )
        XCTAssertEqual(tour.step, .submitSearch)
        tour.receive(.searchSubmitted("Salve"))
        XCTAssertEqual(tour.step, .submitSearch)
        tour.receive(.searchSubmitted("  salve regina  "))
        XCTAssertEqual(tour.step, .chooseChants)
        tour.receive(.searchCategorySelected("hymns"))
        XCTAssertEqual(tour.step, .chooseChants)
        tour.receive(.searchCategorySelected("chants"))
        XCTAssertEqual(tour.step, .openSearchResult)
        tour.receive(.searchResultOpened)
        XCTAssertEqual(tour.step, .chooseFirstChantSetting)
        tour.receive(.searchChantOpened("setting-a"))
        XCTAssertEqual(tour.step, .returnFromFirstChant)
        tour.receive(.searchChantClosed("setting-a"))
        XCTAssertEqual(tour.step, .chooseSecondChantSetting)
        tour.receive(.searchChantOpened("setting-a"))
        XCTAssertEqual(tour.step, .chooseSecondChantSetting)
        tour.receive(.searchChantOpened("setting-b"))
        XCTAssertEqual(tour.step, .returnFromSecondChant)
        tour.receive(.searchChantClosed("setting-b"))
        XCTAssertEqual(tour.step, .returnToSearchResults)
        tour.receive(.searchDetailClosed)
        XCTAssertEqual(tour.step, .closeSearch)

        tour.receive(.searchClosed)
        XCTAssertEqual(tour.step, .openSettings)

        tour.receive(.settingsOpened)
        tour.receive(.hourDisplayChanged(.wheel))
        XCTAssertEqual(tour.step, .changeHourDisplay)
        tour.receive(.hourDisplayChanged(.sunDial))
        tour.receive(.appearanceChanged(.dynamic))
        XCTAssertEqual(tour.step, .changeAppearance)
        tour.receive(.appearanceChanged(.system))
        tour.receive(.settingsClosed)
        tour.receive(.settingsOpened)
        tour.receive(.hourDisplayChanged(.wheel))
        tour.receive(.appearanceChanged(.dynamic))
        XCTAssertEqual(tour.step, .restoreAutomaticTracking)
        tour.receive(.automaticHourSelectionChanged(true))
        XCTAssertEqual(tour.step, .openAbout)
        XCTAssertEqual(tour.step?.target, .settingsAbout)
        XCTAssertEqual(
            tour.instruction,
            "Tap the info button in the top-left corner to open About Hours."
        )
        tour.receive(.aboutOpened)
        XCTAssertEqual(tour.step, .aboutReplay)
        XCTAssertTrue(tour.isFinalStep)
    }

    func testSearchRequiresSubmissionAndNonemptyResults() {
        let tour = makeTourAtSearchStep()

        tour.receive(.searchSubmitted("Salve Regina"))
        tour.receive(
            .searchResultsLoaded(query: "Salve Regina", count: 0)
        )
        XCTAssertEqual(tour.step, .submitSearch)
        tour.receive(
            .searchResultsLoaded(query: "Other", count: 12)
        )
        XCTAssertEqual(tour.step, .submitSearch)
        tour.receive(
            .searchResultsLoaded(query: "Salve Regina", count: 2)
        )
        XCTAssertEqual(tour.step, .chooseChants)
    }

    func testSwipeDirectionAndLaterHourAreSafeAtBoundaries() {
        let tour = makeTourThroughCalendarSelection()
        tour.receive(
            .calendarClosed(
                canSwipePrevious: true,
                canSwipeNext: false
            )
        )
        XCTAssertEqual(tour.requiredDaySwipeOffset, -1)
    }

    func testFinishRestoresCompleteStateAndClearsRecovery() async throws {
        let originalDay = LocalDay(year: 2026, month: 8, day: 20)
        let original = snapshot(
            day: originalDay,
            hour: .prime,
            automatic: false,
            hourDisplay: .sunDial,
            appearance: .system,
            reader: AppTourReaderSnapshot(
                day: originalDay,
                hour: .prime,
                scrollOffset: 731.5
            ),
            recentQueries: "[\"Ave Maria\"]",
            recentHits: "[{\"id\":\"original\"}]"
        )
        let repository = AppTourTestRepository(day: originalDay)
        let model = AppModel(
            repository: repository,
            userDefaults: standardDefaults
        )
        let tour = makeTour()
        tour.begin(snapshot: original)

        await tour.finish(
            model: model,
            playback: ChantPlaybackController(
                userDefaults: standardDefaults
            )
        )

        XCTAssertFalse(tour.isActive)
        XCTAssertEqual(model.selectedDay?.date, originalDay)
        XCTAssertEqual(model.selectedHour, .prime)
        XCTAssertFalse(model.automaticallySelectsCurrentOffice)
        XCTAssertTrue(model.isReaderSessionActive)
        XCTAssertEqual(
            model.restoredReaderScrollOffset(
                for: try XCTUnwrap(model.office)
            ),
            731.5
        )
        XCTAssertEqual(
            standardDefaults.string(
                forKey: AppTourPersistence.recentQueriesKey
            ),
            "[\"Ave Maria\"]"
        )
        XCTAssertEqual(
            standardDefaults.string(
                forKey: AppTourPersistence.recentHitsKey
            ),
            "[{\"id\":\"original\"}]"
        )
        XCTAssertEqual(
            appearanceDefaults.string(
                forKey: HoursSharedPreferences.appearanceModeKey
            ),
            AppDisplayMode.system.rawValue
        )
        XCTAssertNil(
            standardDefaults.data(
                forKey: AppTourPersistence.recoverySnapshotKey
            )
        )
        XCTAssertEqual(tour.presentationRequest, .reader)
    }

    func testSkippingAtEarlyAndLateStepsRestoresSnapshot() async {
        let originalDay = LocalDay(year: 2026, month: 8, day: 20)
        let original = snapshot(
            day: originalDay,
            hour: .terce,
            automatic: false,
            recentQueries: "[\"before-tour\"]",
            recentHits: "[\"before-tour-hit\"]"
        )

        for advancesToLateStep in [false, true] {
            let model = AppModel(
                repository: AppTourTestRepository(day: originalDay),
                userDefaults: standardDefaults
            )
            let tour = makeTour()
            tour.begin(snapshot: original)
            if advancesToLateStep {
                tour.receive(.hourSelected(.vespers))
                tour.receive(.officeLoaded(.vespers))
                advanceReaderTour(tour)
                tour.receive(.calendarOpened)
                tour.receive(.calendarMonthAdvanced)
                tour.receive(.calendarGridOpened)
                tour.receive(
                    .calendarClosed(
                        canSwipePrevious: true,
                        canSwipeNext: false
                    )
                )
                advanceToCloseSearch(tour)
            }

            standardDefaults.set(
                "[\"during-tour\"]",
                forKey: AppTourPersistence.recentQueriesKey
            )
            await tour.finish(
                model: model,
                playback: ChantPlaybackController(
                    userDefaults: standardDefaults
                )
            )

            XCTAssertFalse(tour.isActive)
            XCTAssertEqual(model.selectedHour, .terce)
            XCTAssertEqual(
                standardDefaults.string(
                    forKey: AppTourPersistence.recentQueriesKey
                ),
                "[\"before-tour\"]"
            )
            XCTAssertNil(
                standardDefaults.data(
                    forKey: AppTourPersistence.recoverySnapshotKey
                )
            )
        }
    }

    func testFinishingPreservesMountedTargetFrameForSameSessionReplay() async {
        let day = LocalDay(year: 2026, month: 8, day: 20)
        let original = snapshot(
            day: day,
            hour: .compline,
            automatic: false
        )
        let model = AppModel(
            repository: AppTourTestRepository(day: day),
            userDefaults: standardDefaults
        )
        let tour = makeTour()
        let wheelFrame = CGRect(x: 0, y: 320, width: 390, height: 520)

        tour.report(frame: wheelFrame, for: .hourSelector)
        tour.begin(snapshot: original)
        await tour.finish(
            model: model,
            playback: ChantPlaybackController(
                userDefaults: standardDefaults
            )
        )

        tour.begin(snapshot: original)

        XCTAssertEqual(tour.frame(for: .hourSelector), wheelFrame)
    }

    func testInterruptedTourRestoresPersistentValuesBeforeRelaunch() throws {
        let original = snapshot(
            day: LocalDay(year: 2026, month: 8, day: 20),
            hour: .compline,
            automatic: false,
            hourDisplay: .sunDial,
            appearance: .system,
            reader: nil,
            recentQueries: "[\"original\"]",
            recentHits: "[\"hit\"]"
        )
        standardDefaults.set(
            try JSONEncoder().encode(original),
            forKey: AppTourPersistence.recoverySnapshotKey
        )
        standardDefaults.set("tour", forKey: AppTourPersistence.recentQueriesKey)
        appearanceDefaults.set(
            AppDisplayMode.dynamic.rawValue,
            forKey: HoursSharedPreferences.appearanceModeKey
        )

        let recovered = AppTourPersistence.recoverInterruptedSnapshot(
            standardDefaults: standardDefaults,
            appearanceDefaults: appearanceDefaults
        )

        XCTAssertEqual(recovered, original)
        XCTAssertEqual(
            standardDefaults.string(
                forKey: AppTourPersistence.hourDisplayKey
            ),
            HourSelectionViewMode.sunDial.rawValue
        )
        XCTAssertEqual(
            appearanceDefaults.string(
                forKey: HoursSharedPreferences.appearanceModeKey
            ),
            AppDisplayMode.system.rawValue
        )
        XCTAssertEqual(
            standardDefaults.string(
                forKey: AppTourPersistence.recentQueriesKey
            ),
            "[\"original\"]"
        )
        XCTAssertFalse(
            standardDefaults.bool(
                forKey: AppModel.readerIsPresentedKey
            )
        )
    }

    private func makeTour() -> AppTourCoordinator {
        AppTourCoordinator(
            standardDefaults: standardDefaults,
            appearanceDefaults: appearanceDefaults,
            cantorGuideAppreciationDelay: .zero,
            transitionDelayOverride: .zero
        )
    }

    private func snapshot(
        day: LocalDay,
        hour: OfficeHour = .lauds,
        automatic: Bool = true,
        hourDisplay: HourSelectionViewMode = .wheel,
        appearance: AppDisplayMode = .dynamic,
        reader: AppTourReaderSnapshot? = nil,
        recentQueries: String = "[]",
        recentHits: String = "[]"
    ) -> AppTourSnapshot {
        AppTourSnapshot(
            selectedDay: day,
            selectedHour: hour,
            automaticallySelectsCurrentOffice: automatic,
            hourDisplay: hourDisplay,
            appearance: appearance,
            reader: reader,
            recentQueriesJSON: recentQueries,
            recentHitsJSON: recentHits
        )
    }

    private func makeTourAtSearchStep() -> AppTourCoordinator {
        let tour = makeTour()
        tour.begin(
            snapshot: snapshot(
                day: LocalDay(year: 2026, month: 8, day: 20)
            )
        )
        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))
        advanceReaderTour(tour)
        tour.receive(.calendarOpened)
        tour.receive(.calendarMonthAdvanced)
        tour.receive(.calendarGridOpened)
        tour.receive(
            .calendarClosed(
                canSwipePrevious: true,
                canSwipeNext: true
            )
        )
        tour.receive(.daySwiped(1))
        tour.receive(.searchOpened)
        return tour
    }

    private func makeTourThroughCalendarSelection()
        -> AppTourCoordinator {
        let tour = makeTour()
        tour.begin(
            snapshot: snapshot(
                day: LocalDay(year: 2026, month: 8, day: 20)
            )
        )
        tour.receive(.hourSelected(.vespers))
        tour.receive(.officeLoaded(.vespers))
        advanceReaderTour(tour)
        tour.receive(.calendarOpened)
        tour.receive(.calendarMonthAdvanced)
        tour.receive(.calendarGridOpened)
        return tour
    }

    private func advanceToCloseSearch(_ tour: AppTourCoordinator) {
        tour.receive(.daySwiped(-1))
        tour.receive(.searchOpened)
        tour.receive(.searchSubmitted("Salve Regina"))
        tour.receive(
            .searchResultsLoaded(query: "Salve Regina", count: 1)
        )
        tour.receive(.searchCategorySelected("chants"))
        tour.receive(.searchResultOpened)
        tour.receive(.searchChantOpened("setting-a"))
        tour.receive(.searchChantClosed("setting-a"))
        tour.receive(.searchChantOpened("setting-b"))
        tour.receive(.searchChantClosed("setting-b"))
        tour.receive(.searchDetailClosed)
        XCTAssertEqual(tour.step, .closeSearch)
    }

    private func advanceReaderTour(_ tour: AppTourCoordinator) {
        tour.receive(.readerOpened)
        tour.receive(.cantorGuideOpened)
        tour.receive(.scholaPitchChanged(.a))
        XCTAssertEqual(tour.step, .changeCantorPitch)
        tour.receive(.scholaPitchChanged(.g))
        tour.receive(.cantorGuideClosed)
        tour.receive(.readerContentsOpened)
        tour.receive(.readerSectionSelected("Psalmi"))
        XCTAssertEqual(tour.step, .chooseOratio)
        tour.receive(.readerSectionSelected("Oratio"))
        tour.receive(.readerOptionsOpened)
        tour.receive(.englishVisibilityChanged(false))
        XCTAssertEqual(tour.step, .enableEnglish)
        tour.receive(.englishVisibilityChanged(true))
        tour.receive(.readerOptionsClosed)
        tour.receive(.readerClosed)
    }
}

private actor AppTourTestRepository: ContentRepository {
    let liturgicalDay: LiturgicalDay

    init(day: LocalDay) {
        liturgicalDay = LiturgicalDay(
            date: day,
            observanceID: "tour-test",
            titleLatin: "Dies Testis",
            season: "Test"
        )
    }

    func availableDays() -> [LiturgicalDay] {
        [liturgicalDay]
    }

    func day(on date: LocalDay) throws -> LiturgicalDay {
        guard date == liturgicalDay.date else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return liturgicalDay
    }

    func office(
        on date: LocalDay,
        hour: OfficeHour
    ) throws -> OfficeDocument {
        guard date == liturgicalDay.date else {
            throw ContentRepositoryError.contentUnavailable(date, hour)
        }
        return OfficeDocument(
            id: "\(date)-\(hour.rawValue)",
            date: date,
            hour: hour,
            titleLatin: hour.latinTitle,
            contextLabel: "Tour Test",
            sections: []
        )
    }
}
