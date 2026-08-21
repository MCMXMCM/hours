import HoursCore
import SwiftUI
import XCTest
@testable import Hours

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDisplayModesResolveExpectedAppearance() {
        XCTAssertEqual(
            AppDisplayMode.allCases,
            [.dynamic, .system]
        )
        XCTAssertEqual(
            AppDisplayMode.dynamic.preferredColorScheme(for: .matins),
            .dark
        )
        XCTAssertEqual(
            AppDisplayMode.dynamic.preferredColorScheme(for: .sext),
            .light
        )

        for hour in OfficeHour.allCases {
            XCTAssertNil(
                AppDisplayMode.system.preferredColorScheme(for: hour)
            )
        }

        XCTAssertTrue(AppDisplayMode.dynamic.showsAmbientSky)
        XCTAssertFalse(AppDisplayMode.system.showsAmbientSky)
    }

    func testPresentedReaderControlsDynamicAppearanceAfterRestoration() {
        XCTAssertEqual(
            RootView.appearanceHour(
                presentedOfficeHour: .sext,
                hourSelectionView: .wheel,
                displayedHour: .compline,
                selectedHour: .sext
            ),
            .sext
        )
        XCTAssertEqual(
            RootView.appearanceHour(
                presentedOfficeHour: .compline,
                hourSelectionView: .wheel,
                displayedHour: .sext,
                selectedHour: .compline
            ),
            .compline
        )
    }

    func testHomeAppearanceStillFollowsTheActiveHourSelector() {
        XCTAssertEqual(
            RootView.appearanceHour(
                presentedOfficeHour: nil,
                hourSelectionView: .wheel,
                displayedHour: .vespers,
                selectedHour: .prime
            ),
            .vespers
        )
        XCTAssertEqual(
            RootView.appearanceHour(
                presentedOfficeHour: nil,
                hourSelectionView: .sunDial,
                displayedHour: .vespers,
                selectedHour: .prime
            ),
            .prime
        )
    }

    func testSundialShadowUsesTheEffectiveAppearance() {
        XCTAssertFalse(
            AppDisplayMode.showsSundialShadow(in: .dark)
        )
        XCTAssertTrue(
            AppDisplayMode.showsSundialShadow(in: .light)
        )
    }

    func testHourDisplayPresentsSundialBeforeWheel() {
        XCTAssertEqual(
            HourSelectionViewMode.allCases,
            [.sunDial, .wheel]
        )
    }

    func testAutomaticHourRangesCoverTheSolarDialDayAndNight() {
        XCTAssertEqual(
            OfficeHour.allCases.map(\.customaryTimeRange),
            [
                "12am – 4am",
                "4am – 6am",
                "6am – 8am",
                "8am – 10am",
                "10am – 1pm",
                "1pm – 4pm",
                "4pm – 8pm",
                "8pm – 12am",
            ]
        )
    }

    func testCurrentHourUsesTheSolarDialBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = DateComponents(year: 2026, month: 7, day: 27)

        func hour(at hour: Int, minute: Int) throws -> OfficeHour {
            var components = day
            components.hour = hour
            components.minute = minute
            return OfficeHour.current(
                at: try XCTUnwrap(calendar.date(from: components)),
                calendar: calendar
            )
        }

        XCTAssertEqual(try hour(at: 0, minute: 0), .matins)
        XCTAssertEqual(try hour(at: 3, minute: 59), .matins)
        XCTAssertEqual(try hour(at: 4, minute: 0), .lauds)
        XCTAssertEqual(try hour(at: 6, minute: 0), .prime)
        XCTAssertEqual(try hour(at: 8, minute: 0), .terce)
        XCTAssertEqual(try hour(at: 10, minute: 0), .sext)
        XCTAssertEqual(try hour(at: 13, minute: 0), .none)
        XCTAssertEqual(try hour(at: 16, minute: 0), .vespers)
        XCTAssertEqual(try hour(at: 19, minute: 59), .vespers)
        XCTAssertEqual(try hour(at: 20, minute: 0), .compline)
        XCTAssertEqual(try hour(at: 23, minute: 59), .compline)
    }

    func testCurrentOfficeDayAdvancesAtLaudsInsteadOfMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )

        func officeDay(
            year: Int = 2026,
            month: Int = 7,
            day: Int,
            hour: Int,
            minute: Int
        ) throws -> LocalDay {
            let date = try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        year: year,
                        month: month,
                        day: day,
                        hour: hour,
                        minute: minute
                    )
                )
            )
            return LocalDay.currentOfficeDay(
                at: date,
                calendar: calendar
            )
        }

        let monday = LocalDay(year: 2026, month: 7, day: 27)
        let tuesday = LocalDay(year: 2026, month: 7, day: 28)

        XCTAssertEqual(
            try officeDay(day: 27, hour: 23, minute: 59),
            monday
        )
        XCTAssertEqual(
            try officeDay(day: 28, hour: 0, minute: 0),
            monday
        )
        XCTAssertEqual(
            try officeDay(day: 28, hour: 3, minute: 59),
            monday
        )
        XCTAssertEqual(
            try officeDay(day: 28, hour: 4, minute: 0),
            tuesday
        )
    }

    func testCurrentOfficeDayUsesCalendarDaysAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Chicago")
        )
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 3,
                    day: 8,
                    hour: 3,
                    minute: 30
                )
            )
        )

        XCTAssertEqual(
            LocalDay.currentOfficeDay(
                at: date,
                calendar: calendar
            ),
            LocalDay(year: 2026, month: 3, day: 7)
        )
    }
}
