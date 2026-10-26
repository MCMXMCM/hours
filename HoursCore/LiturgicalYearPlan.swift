import Foundation

/// Under fixed rubrics the Office of a civil year follows from two facts only:
/// the date of Easter and whether the year is a leap year. Thirty-five Easter
/// dates and two lengths of year make seventy year types, and every year of
/// one type has, date for date, the same Office (the Martyrology's Moon and
/// year excepted, which `RomanMartyrologyCalendar` supplies).
public struct LiturgicalYearType: Hashable, Sendable {
    public let easterMonth: Int
    public let easterDay: Int
    public let isLeapYear: Bool

    /// The years for which the Gregorian computus is defined here.
    public static let supportedYears = 1583...4099

    public init(year: Int) {
        let easter = Roman1960CalendarMath.gregorianEaster(year: year)
        easterMonth = easter.month
        easterDay = easter.day
        isLeapYear = Self.isLeapYear(year)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 4)
            && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    }
}

/// The civil years a perennial edition stores, and the years it thereby
/// serves: one stored year of each year type, from which every served year
/// of that type is read. A year the edition first serves is stored as itself
/// wherever the source could render it, so the plan is the identity over an
/// edition's reviewed window.
public struct PerennialYearPlan: Hashable, Sendable {
    public let servedYears: ClosedRange<Int>
    public let storedYears: [Int]
    private let storedYearByType: [LiturgicalYearType: Int]

    public init(servedYears: ClosedRange<Int>, storedYears: [Int]) throws {
        let supported = LiturgicalYearType.supportedYears
        guard supported.contains(servedYears.lowerBound),
              supported.contains(servedYears.upperBound),
              !storedYears.isEmpty,
              storedYears.allSatisfy(supported.contains),
              zip(storedYears, storedYears.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw ContentRepositoryError.invalidContent(
                "The corpus's stored years are not an ordered list of civil years."
            )
        }
        var byType: [LiturgicalYearType: Int] = [:]
        for year in storedYears {
            let type = LiturgicalYearType(year: year)
            if let other = byType[type] {
                throw ContentRepositoryError.invalidContent(
                    "The corpus stores \(other) and \(year), which are one year type."
                )
            }
            byType[type] = year
        }
        for year in servedYears where byType[LiturgicalYearType(year: year)] == nil {
            throw ContentRepositoryError.invalidContent(
                "The corpus serves \(year) but stores no year of its type."
            )
        }
        self.servedYears = servedYears
        self.storedYears = storedYears
        self.storedYearByType = byType
    }

    /// The first and last civil dates served.
    public var coverage: ClosedRange<LocalDay> {
        LocalDay(year: servedYears.lowerBound, month: 1, day: 1)
            ... LocalDay(year: servedYears.upperBound, month: 12, day: 31)
    }

    /// The stored year from which a year is read; nil when it is not served.
    public func storedYear(for year: Int) -> Int? {
        guard servedYears.contains(year) else { return nil }
        return storedYearByType[LiturgicalYearType(year: year)]
    }

    /// The stored civil date from which a date is read; nil when it is not
    /// served. Years of one type are of one length, so the day of the month
    /// exists in both.
    public func storedDay(for day: LocalDay) -> LocalDay? {
        storedYear(for: day.year).map {
            LocalDay(year: $0, month: day.month, day: day.day)
        }
    }

    /// The first served year read from a stored year; nil for a year the
    /// edition does not store, or stores for no year it serves.
    public func firstServedYear(storedAs storedYear: Int) -> Int? {
        guard storedYears.contains(storedYear) else { return nil }
        let type = LiturgicalYearType(year: storedYear)
        return servedYears.first { LiturgicalYearType(year: $0) == type }
    }

    /// A range of served dates as the stored ranges that hold it, one for
    /// each civil year it touches, in order. Dates outside the served years
    /// are left out.
    public func storedRanges(
        for range: ClosedRange<LocalDay>
    ) -> [(servedYear: Int, stored: ClosedRange<LocalDay>)] {
        let coverage = self.coverage
        guard range.lowerBound <= coverage.upperBound,
              range.upperBound >= coverage.lowerBound else {
            return []
        }
        let lower = max(range.lowerBound, coverage.lowerBound)
        let upper = min(range.upperBound, coverage.upperBound)
        return (lower.year...upper.year).compactMap { year in
            guard let stored = storedYear(for: year) else { return nil }
            let first = max(lower, LocalDay(year: year, month: 1, day: 1))
            let last = min(upper, LocalDay(year: year, month: 12, day: 31))
            return (
                year,
                LocalDay(year: stored, month: first.month, day: first.day)
                    ... LocalDay(year: stored, month: last.month, day: last.day)
            )
        }
    }
}

public extension ContentCoverage {
    /// The plan of a perennial edition; nil where every date served is stored.
    func yearPlan() throws -> PerennialYearPlan? {
        guard let storedYears else { return nil }
        guard startDate.month == 1, startDate.day == 1,
              endDate.month == 12, endDate.day == 31,
              startDate.year <= endDate.year else {
            throw ContentRepositoryError.invalidContent(
                "A perennial corpus must serve whole civil years."
            )
        }
        return try PerennialYearPlan(
            servedYears: startDate.year...endDate.year,
            storedYears: storedYears
        )
    }
}
