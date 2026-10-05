@testable import Hours
import HoursCore
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppModel.showsEnglishKey)
        defaults.removeObject(forKey: AppModel.notationScaleKey)
        defaults.removeObject(forKey: AppModel.compactPsalmodyKey)
        defaults.removeObject(
            forKey: AppModel.priestOrDeaconPresentKey
        )
    }

    func testNeumeSizeDefaultsToOneHundredPercent() {
        let model = AppModel()

        XCTAssertEqual(model.notationScale, 1.0)
    }

    func testCompactPsalmodyDefaultsOff() {
        let model = AppModel()

        XCTAssertFalse(model.usesCompactPsalmody)
    }

    func testPrayerOptionsSurviveRelaunch() throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let model = AppModel(userDefaults: defaults)

        model.showsEnglish = true
        model.notationScale = 1.4
        model.usesCompactPsalmody = true
        model.isPriestOrDeaconPresent = true

        let relaunchedModel = AppModel(userDefaults: defaults)
        XCTAssertTrue(relaunchedModel.showsEnglish)
        XCTAssertEqual(relaunchedModel.notationScale, 1.4)
        XCTAssertTrue(relaunchedModel.usesCompactPsalmody)
        XCTAssertTrue(relaunchedModel.isPriestOrDeaconPresent)
    }

    func testCurrentOfficeSelectionAfterMidnightOpensMatinsOfTheNewDay() async throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )
        let afterMidnight = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 28,
                    hour: 1
                )
            )
        )
        let model = AppModel(userDefaults: defaults)

        await model.selectCurrentOffice(
            at: afterMidnight,
            calendar: calendar
        )

        // Matins begins the liturgical day, which runs from midnight to
        // midnight (Rubricae generales 1960, n. 4).
        XCTAssertEqual(model.selectedHour, .matins)
        XCTAssertEqual(
            LocalDay(model.selectedCivilDate, calendar: calendar),
            LocalDay(year: 2026, month: 7, day: 28)
        )
    }

    func testManualHourAndAutomaticSelectionPreferenceSurviveRelaunch() throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let launchDate = Date(timeIntervalSince1970: 0)
        let model = AppModel(
            userDefaults: defaults,
            date: launchDate
        )

        model.setAutomaticOfficeSelection(false)
        model.selectedHour = .compline

        let relaunchedModel = AppModel(
            userDefaults: defaults,
            date: launchDate
        )
        XCTAssertFalse(
            relaunchedModel.automaticallySelectsCurrentOffice
        )
        XCTAssertEqual(relaunchedModel.selectedHour, .compline)
    }

    func testCurrentOfficeRefreshCannotOverrideManualSelection() async throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )
        let currentLauds = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 28,
                    hour: 5
                )
            )
        )
        let model = AppModel(
            userDefaults: defaults,
            date: currentLauds
        )
        model.setAutomaticOfficeSelection(false)
        model.selectedHour = .compline

        await model.selectCurrentOffice(
            at: currentLauds,
            calendar: calendar
        )

        XCTAssertEqual(model.selectedHour, .compline)
    }

    func testSelectingDateEntersManualModeUntilAutomaticIsRestored()
        async throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )
        let currentDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 8,
                    day: 31,
                    hour: 10
                )
            )
        )
        let christmas = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 12,
                    day: 25,
                    hour: 12
                )
            )
        )
        let model = AppModel(
            userDefaults: defaults,
            date: currentDate
        )

        await model.select(civilDate: christmas)

        XCTAssertFalse(model.automaticallySelectsCurrentOffice)
        XCTAssertFalse(
            defaults.bool(
                forKey: AppModel.automaticOfficeSelectionKey
            )
        )
        XCTAssertEqual(
            LocalDay(model.selectedCivilDate, calendar: calendar),
            LocalDay(year: 2026, month: 12, day: 25)
        )

        await model.selectCurrentOffice(
            at: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(
            LocalDay(model.selectedCivilDate, calendar: calendar),
            LocalDay(year: 2026, month: 12, day: 25)
        )

        model.setAutomaticOfficeSelection(true)
        await model.selectCurrentOffice(
            at: currentDate,
            calendar: calendar
        )

        XCTAssertTrue(model.automaticallySelectsCurrentOffice)
        XCTAssertEqual(
            LocalDay(model.selectedCivilDate, calendar: calendar),
            LocalDay(year: 2026, month: 8, day: 31)
        )
    }

    func testOpenReaderSessionSurvivesRelaunchWithAutomaticSelection() throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let office = OfficeDocument(
            id: "2026-07-28-matins",
            date: LocalDay(year: 2026, month: 7, day: 28),
            hour: .matins,
            titleLatin: "Ad Matutinum",
            contextLabel: "Test",
            sections: []
        )
        let model = AppModel(userDefaults: defaults)

        model.beginReaderSession(for: office)
        model.updateReaderScrollOffset(842.5, for: office)

        let relaunchedModel = AppModel(
            userDefaults: defaults,
            date: Date(timeIntervalSince1970: 12 * 60 * 60)
        )
        XCTAssertTrue(relaunchedModel.automaticallySelectsCurrentOffice)
        XCTAssertTrue(relaunchedModel.isReaderSessionActive)
        XCTAssertEqual(relaunchedModel.selectedHour, .matins)
        XCTAssertEqual(
            relaunchedModel.restoredReaderScrollOffset(for: office),
            842.5
        )
        XCTAssertTrue(relaunchedModel.shouldRestoreReader(for: office))
    }

    func testReaderRestoresExactDayHourAndAnchorAfterStartupForEveryTradition() async throws {
        for tradition in OfficeTradition.allCases {
            let suiteName = "AppModelTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(tradition.rawValue, forKey: AppModel.officeTraditionKey)
            let day = LocalDay(year: 2026, month: 7, day: 28)
            let repository = CountingContentRepository(day: day)
            let model = AppModel(repository: repository, userDefaults: defaults)
            _ = await model.start()
            await model.selectOffice(on: day, hour: .matins)
            let office = try XCTUnwrap(model.office)
            let anchor = OfficeReaderScrollAnchor(sectionID: "lesson-2", viewportY: -318.5)
            model.beginReaderSession(for: office)
            model.updateReaderScrollOffset(8_420, for: office, anchor: anchor)

            let relaunched = AppModel(repository: repository, userDefaults: defaults)
            _ = await relaunched.start()
            await relaunched.refreshAfterBecomingActive()
            XCTAssertEqual(relaunched.officeTradition, tradition)
            XCTAssertEqual(relaunched.office?.date, day)
            XCTAssertEqual(relaunched.office?.hour, .matins)
            XCTAssertTrue(relaunched.shouldRestoreReader(for: office))
            XCTAssertEqual(relaunched.restoredReaderScrollOffset(for: office), 8_420)
            XCTAssertEqual(relaunched.restoredReaderScrollAnchor(for: office), anchor)
            relaunched.endReaderSession()
            XCTAssertNil(defaults.data(forKey: AppModel.readerScrollAnchorKey))
        }
    }

    func testAutomaticRefreshCannotOverrideAnOpenReader() async throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )
        let morning = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 28,
                    hour: 9
                )
            )
        )
        let office = OfficeDocument(
            id: "2026-07-27-matins",
            date: LocalDay(year: 2026, month: 7, day: 27),
            hour: .matins,
            titleLatin: "Ad Matutinum",
            contextLabel: "Test",
            sections: []
        )
        let model = AppModel(
            userDefaults: defaults,
            date: morning
        )
        model.beginReaderSession(for: office)

        await model.selectCurrentOffice(at: morning, calendar: calendar)

        XCTAssertEqual(model.selectedHour, .matins)

        model.endReaderSession()
        await model.selectCurrentOffice(at: morning, calendar: calendar)

        XCTAssertFalse(model.isReaderSessionActive)
        XCTAssertEqual(model.selectedHour, .terce)
    }

    func testSelectingLoadedOfficeDoesNotReloadContent() async throws {
        let day = LocalDay(year: 2026, month: 7, day: 28)
        let repository = CountingContentRepository(day: day)
        let model = AppModel(repository: repository)
        model.selectedHour = .lauds

        await model.select(civilDate: try XCTUnwrap(day.date))
        await model.select(hour: .lauds)

        let counts = await repository.requestCounts()
        XCTAssertEqual(counts.day, 1)
        XCTAssertEqual(counts.office, 1)
    }

    func testChangingOnlyHourReusesLoadedLiturgicalDay() async throws {
        let day = LocalDay(year: 2026, month: 7, day: 28)
        let repository = CountingContentRepository(day: day)
        let model = AppModel(repository: repository)
        model.selectedHour = .lauds

        await model.select(civilDate: try XCTUnwrap(day.date))
        await model.select(hour: .prime)

        let counts = await repository.requestCounts()
        XCTAssertEqual(counts.day, 1)
        XCTAssertEqual(counts.office, 2)
        XCTAssertEqual(model.office?.hour, .prime)
    }

    func testFailedOfficeSelectionKeepsDayAndRecoversOnActivation()
        async throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let day = LocalDay(year: 2026, month: 7, day: 28)
        let repository = CountingContentRepository(
            day: day,
            failingOnceFor: .prime
        )
        let model = AppModel(
            repository: repository,
            userDefaults: defaults
        )
        model.setAutomaticOfficeSelection(false)

        await model.select(civilDate: try XCTUnwrap(day.date))
        await model.select(hour: .prime)

        XCTAssertEqual(model.selectedDay?.date, day)
        XCTAssertNil(model.office)
        XCTAssertNotNil(model.errorMessage)

        await model.refreshAfterBecomingActive()

        let counts = await repository.requestCounts()
        XCTAssertEqual(counts.office, 3)
        XCTAssertEqual(model.selectedDay?.date, day)
        XCTAssertEqual(model.office?.hour, .prime)
        XCTAssertNil(model.errorMessage)
    }

    func testSearchUsageSelectsItsExactDayAndOffice() async throws {
        let day = LocalDay(year: 2026, month: 1, day: 8)
        let repository = CountingContentRepository(day: day)
        let model = AppModel(repository: repository)

        await model.selectOffice(on: day, hour: .compline)

        XCTAssertEqual(model.selectedDay?.date, day)
        XCTAssertEqual(model.office?.date, day)
        XCTAssertEqual(model.office?.hour, .compline)
        XCTAssertEqual(model.selectedHour, .compline)
    }

    func testReturningToLoadedOfficeCancelsSupersededSelection() async throws {
        let day = LocalDay(year: 2026, month: 7, day: 28)
        let repository = CountingContentRepository(
            day: day,
            delayedHour: .prime
        )
        let model = AppModel(repository: repository)
        model.selectedHour = .lauds
        await model.select(civilDate: try XCTUnwrap(day.date))

        let pendingSelection = Task {
            await model.select(hour: .prime)
        }
        try await Task.sleep(for: .milliseconds(10))
        await model.select(hour: .lauds)
        await pendingSelection.value

        XCTAssertEqual(model.selectedHour, .lauds)
        XCTAssertEqual(model.office?.hour, .lauds)
        XCTAssertFalse(model.isLoading)
    }

    func testAdjacentAvailableDayUsesLoadedCorpusIndex() async throws {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let model = AppModel(userDefaults: defaults)

        await model.start()
        await model.selectOffice(
            on: LocalDay(year: 2026, month: 8, day: 6),
            hour: .lauds
        )

        XCTAssertEqual(
            model.availableDay(offsetFromSelectedBy: -1)?.date,
            LocalDay(year: 2026, month: 8, day: 5)
        )
        XCTAssertEqual(
            model.availableDay(offsetFromSelectedBy: 1)?.date,
            LocalDay(year: 2026, month: 8, day: 7)
        )
    }
}

private actor CountingContentRepository: ContentRepository {
    private let liturgicalDay: LiturgicalDay
    private let delayedHour: OfficeHour?
    private let failingOnceHour: OfficeHour?
    private var hasFailedRequestedHour = false
    private var dayRequests = 0
    private var officeRequests = 0

    init(
        day: LocalDay,
        delayedHour: OfficeHour? = nil,
        failingOnceFor failingOnceHour: OfficeHour? = nil
    ) {
        liturgicalDay = LiturgicalDay(
            date: day,
            observanceID: "test-day",
            titleLatin: "Dies Testis",
            season: "Test"
        )
        self.delayedHour = delayedHour
        self.failingOnceHour = failingOnceHour
    }

    func availableDays() -> [LiturgicalDay] {
        [liturgicalDay]
    }

    func day(on date: LocalDay) throws -> LiturgicalDay {
        dayRequests += 1
        guard date == liturgicalDay.date else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return liturgicalDay
    }

    func office(
        on date: LocalDay,
        hour: OfficeHour
    ) async throws -> OfficeDocument {
        officeRequests += 1
        guard date == liturgicalDay.date else {
            throw ContentRepositoryError.contentUnavailable(date, hour)
        }
        if hour == delayedHour {
            try await Task.sleep(for: .milliseconds(80))
        }
        if hour == failingOnceHour, !hasFailedRequestedHour {
            hasFailedRequestedHour = true
            throw ContentRepositoryError.contentUnavailable(date, hour)
        }
        return OfficeDocument(
            id: "\(date)-\(hour.rawValue)",
            date: date,
            hour: hour,
            titleLatin: hour.latinTitle,
            contextLabel: "Test",
            sections: []
        )
    }

    func requestCounts() -> (day: Int, office: Int) {
        (dayRequests, officeRequests)
    }
}
