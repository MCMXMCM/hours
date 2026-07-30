import XCTest
@testable import Hours
import HoursCore

@MainActor
final class OfficeCalendarMathTests: XCTestCase {
    func testDaySlotsUseTheCalendarsFirstWeekday() throws {
        let calendar = testCalendar
        let july = try date(
            year: 2026,
            month: 7,
            day: 19,
            calendar: calendar
        )

        let slots = OfficeCalendarMath.daySlots(
            in: july,
            calendar: calendar
        )

        XCTAssertEqual(slots.count, 42)
        XCTAssertEqual(slots.prefix { $0 == nil }.count, 3)
        XCTAssertEqual(slots.compactMap(\.self).count, 31)
        XCTAssertEqual(
            calendar.component(
                .day,
                from: try XCTUnwrap(slots.compactMap(\.self).first)
            ),
            1
        )
    }

    func testMonthComparisonIncludesTheYear() throws {
        let calendar = testCalendar
        let july2026 = try date(
            year: 2026,
            month: 7,
            day: 1,
            calendar: calendar
        )
        let laterInJuly = try date(
            year: 2026,
            month: 7,
            day: 31,
            calendar: calendar
        )
        let july2027 = try date(
            year: 2027,
            month: 7,
            day: 1,
            calendar: calendar
        )

        XCTAssertTrue(
            OfficeCalendarMath.isSameMonth(
                july2026,
                as: laterInJuly,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            OfficeCalendarMath.isSameMonth(
                july2026,
                as: july2027,
                calendar: calendar
            )
        )
    }

    func testMonthIntersectionHonorsPartialBoundaryMonths() throws {
        let calendar = testCalendar
        let range = try date(
            year: 2026,
            month: 7,
            day: 15,
            calendar: calendar
        )...date(
            year: 2026,
            month: 8,
            day: 20,
            calendar: calendar
        )

        for (month, expected) in [
            (6, false),
            (7, true),
            (8, true),
            (9, false),
        ] {
            XCTAssertEqual(
                OfficeCalendarMath.month(
                    try date(
                        year: 2026,
                        month: month,
                        day: 1,
                        calendar: calendar
                    ),
                    intersects: range,
                    calendar: calendar
                ),
                expected
            )
        }
    }

    func testMonthOfficeDaysReturnsOnlySelectedMonthInSourceOrder() throws {
        let calendar = testCalendar
        let days = [
            liturgicalDay(year: 2026, month: 6, day: 30),
            liturgicalDay(year: 2026, month: 7, day: 1),
            liturgicalDay(year: 2026, month: 7, day: 31),
            liturgicalDay(year: 2026, month: 8, day: 1),
        ]

        let julyDays = MonthOfficeDays.days(
            containing: try date(
                year: 2026,
                month: 7,
                day: 19,
                calendar: calendar
            ),
            from: days,
            calendar: calendar
        )

        XCTAssertEqual(
            julyDays.map(\.date),
            [
                LocalDay(year: 2026, month: 7, day: 1),
                LocalDay(year: 2026, month: 7, day: 31),
            ]
        )
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day
                )
            )
        )
    }

    private func liturgicalDay(
        year: Int,
        month: Int,
        day: Int
    ) -> LiturgicalDay {
        LiturgicalDay(
            date: LocalDay(year: year, month: month, day: day),
            observanceID: "\(year)-\(month)-\(day)",
            titleLatin: "Feria",
            rank: .fourthClass,
            season: "Test"
        )
    }
}
