@testable import Hours
import HoursCore
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    func testNeumeSizeDefaultsToOneHundredPercent() {
        let model = AppModel()

        XCTAssertEqual(model.notationScale, 1.0)
    }

    func testCurrentOfficeSelectionKeepsMatinsOnThePriorDate() async throws {
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
        let model = AppModel()

        await model.selectCurrentOffice(
            at: afterMidnight,
            calendar: calendar
        )

        XCTAssertEqual(model.selectedHour, .matins)
        XCTAssertEqual(
            LocalDay(model.selectedCivilDate, calendar: calendar),
            LocalDay(year: 2026, month: 7, day: 27)
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
}

private actor CountingContentRepository: ContentRepository {
    private let liturgicalDay: LiturgicalDay
    private let delayedHour: OfficeHour?
    private var dayRequests = 0
    private var officeRequests = 0

    init(
        day: LocalDay,
        delayedHour: OfficeHour? = nil
    ) {
        liturgicalDay = LiturgicalDay(
            date: day,
            observanceID: "test-day",
            titleLatin: "Dies Testis",
            season: "Test"
        )
        self.delayedHour = delayedHour
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
