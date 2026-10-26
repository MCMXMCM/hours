import Foundation

public enum Roman1960MovableObservance: String, CaseIterable, Sendable {
    case septuagesimaSunday
    case ashWednesday
    case passionSunday
    case palmSunday
    case easterSunday
    case ascension
    case pentecost
    case trinitySunday
    case corpusChristi
    case sacredHeart

    fileprivate var daysFromEaster: Int {
        switch self {
        case .septuagesimaSunday: -63
        case .ashWednesday: -46
        case .passionSunday: -14
        case .palmSunday: -7
        case .easterSunday: 0
        case .ascension: 39
        case .pentecost: 49
        case .trinitySunday: 56
        case .corpusChristi: 60
        case .sacredHeart: 68
        }
    }
}

/// Date arithmetic shared by compiler parity fixtures and a future native
/// 1960-rubrics ordo. It does not resolve occurrence or concurrence by itself.
public enum Roman1960CalendarMath {
    public static func gregorianEaster(year: Int) -> LocalDay {
        precondition((1583...4099).contains(year), "Gregorian computus year is unsupported")
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return LocalDay(year: year, month: month, day: day)
    }

    public static func movableObservances(
        year: Int,
        calendar: Calendar = gregorianUTC
    ) -> [Roman1960MovableObservance: LocalDay] {
        let easter = gregorianEaster(year: year)
        guard let easterDate = easter.date(in: calendar) else { return [:] }
        return Dictionary(uniqueKeysWithValues: Roman1960MovableObservance.allCases.compactMap {
            observance in
            calendar.date(
                byAdding: .day,
                value: observance.daysFromEaster,
                to: easterDate
            ).map { (observance, LocalDay($0, calendar: calendar)) }
        })
    }

    public static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

public struct LiturgicalOrdoParityReport: Equatable, Sendable {
    public let expectedOfficeCount: Int
    public let matchingOfficeCount: Int
    public let calendarEdgeCasesPassed: Bool

    public init(
        expectedOfficeCount: Int,
        matchingOfficeCount: Int,
        calendarEdgeCasesPassed: Bool
    ) {
        self.expectedOfficeCount = expectedOfficeCount
        self.matchingOfficeCount = matchingOfficeCount
        self.calendarEdgeCasesPassed = calendarEdgeCasesPassed
    }

    public var enablesNativeProvider: Bool {
        expectedOfficeCount == 406_152
            && matchingOfficeCount == expectedOfficeCount
            && calendarEdgeCasesPassed
    }
}
