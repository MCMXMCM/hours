import Foundation

/// Compares a calculated ordo with the reviewed schedule without performing
/// any network work. This is intentionally a streaming comparison so the
/// complete 1962–2100 gate does not decode either provider a year at a time.
public enum LiturgicalOrdoParityValidator {
    public static func validate(
        reviewed: any LiturgicalOrdoProvider,
        calculated: any LiturgicalOrdoProvider,
        range: ClosedRange<LocalDay>,
        calendarEdgeCasesPassed: Bool
    ) async throws -> LiturgicalOrdoParityReport {
        var expectedOfficeCount = 0
        var matchingOfficeCount = 0
        var date = range.lowerBound

        while date <= range.upperBound {
            let reviewedDay = try await reviewed.day(on: date)
            let calculatedDay = try await calculated.day(on: date)
            let dayMatches = sameLiturgicalDay(reviewedDay, calculatedDay)

            for hour in OfficeHour.allCases {
                expectedOfficeCount += 1
                let reviewedOffice = try await reviewed.office(on: date, hour: hour)
                let calculatedOffice = try await calculated.office(on: date, hour: hour)
                if dayMatches && sameVisibleOffice(reviewedOffice, calculatedOffice) {
                    matchingOfficeCount += 1
                }
            }

            guard let following = followingDay(after: date) else { break }
            date = following
        }

        return LiturgicalOrdoParityReport(
            expectedOfficeCount: expectedOfficeCount,
            matchingOfficeCount: matchingOfficeCount,
            calendarEdgeCasesPassed: calendarEdgeCasesPassed
        )
    }

    private static func sameLiturgicalDay(
        _ lhs: LiturgicalDay,
        _ rhs: LiturgicalDay
    ) -> Bool {
        lhs.date == rhs.date
            && lhs.observanceID == rhs.observanceID
            && lhs.titleLatin == rhs.titleLatin
            && lhs.titleEnglish == rhs.titleEnglish
            && lhs.rank == rhs.rank
            && lhs.color == rhs.color
            && lhs.season == rhs.season
            && lhs.eveningContext == rhs.eveningContext
            && lhs.commemorations == rhs.commemorations
    }

    private static func sameVisibleOffice(
        _ lhs: OfficeDocument,
        _ rhs: OfficeDocument
    ) -> Bool {
        guard lhs.date == rhs.date,
              lhs.hour == rhs.hour,
              lhs.titleLatin == rhs.titleLatin,
              lhs.titleEnglish == rhs.titleEnglish,
              lhs.contextLabel == rhs.contextLabel,
              lhs.observance == rhs.observance,
              lhs.sections.count == rhs.sections.count else {
            return false
        }

        return zip(lhs.sections, rhs.sections).allSatisfy { left, right in
            left.kind == right.kind
                && left.title == right.title
                && left.titleEnglish == right.titleEnglish
                && left.rubric == right.rubric
                && left.rubricEnglish == right.rubricEnglish
                && left.latin == right.latin
                && left.english == right.english
                && left.chant == right.chant
        }
    }

    static func followingDay(after day: LocalDay) -> LocalDay? {
        let calendar = Roman1960CalendarMath.gregorianUTC
        guard let date = day.date(in: calendar),
              let result = calendar.date(byAdding: .day, value: 1, to: date) else {
            return nil
        }
        return LocalDay(result, calendar: calendar)
    }
}

/// Keeps the reviewed schedule authoritative throughout its coverage and only
/// exposes calculated dates outside it after the exhaustive parity gate has
/// passed. A failed or partial parity report therefore cannot accidentally
/// widen production coverage.
public actor ParityGatedLiturgicalOrdoProvider: LiturgicalOrdoProvider {
    private let reviewed: any LiturgicalOrdoProvider
    private let calculated: any LiturgicalOrdoProvider
    private let parityReport: LiturgicalOrdoParityReport

    public init(
        reviewed: any LiturgicalOrdoProvider,
        calculated: any LiturgicalOrdoProvider,
        parityReport: LiturgicalOrdoParityReport
    ) {
        self.reviewed = reviewed
        self.calculated = calculated
        self.parityReport = parityReport
    }

    public func coverageRange() async throws -> ClosedRange<LocalDay> {
        let reviewedRange = try await reviewed.coverageRange()
        guard parityReport.enablesNativeProvider else { return reviewedRange }
        let calculatedRange = try await calculated.coverageRange()
        let lowerBound = min(
            reviewedRange.lowerBound,
            calculatedRange.lowerBound
        )
        let upperBound = max(
            reviewedRange.upperBound,
            calculatedRange.upperBound
        )
        return lowerBound...upperBound
    }

    public func day(on date: LocalDay) async throws -> LiturgicalDay {
        let reviewedRange = try await reviewed.coverageRange()
        if reviewedRange.contains(date) {
            return try await reviewed.day(on: date)
        }
        return try await calculatedDay(on: date, reviewedRange: reviewedRange)
    }

    public func days(in range: ClosedRange<LocalDay>) async throws -> [LiturgicalDay] {
        let reviewedRange = try await reviewed.coverageRange()
        var result: [LiturgicalDay] = []
        if let overlap = intersection(range, reviewedRange) {
            result.append(contentsOf: try await reviewed.days(in: overlap))
        }

        guard parityReport.enablesNativeProvider else {
            return result.sorted { $0.date < $1.date }
        }
        let calculatedRange = try await calculated.coverageRange()
        let earlierUpperBound = dayBefore(reviewedRange.lowerBound)
        if calculatedRange.lowerBound <= earlierUpperBound,
           range.lowerBound < reviewedRange.lowerBound,
           let earlier = intersection(
               range,
               calculatedRange.lowerBound...earlierUpperBound
           ) {
            result.append(contentsOf: try await calculated.days(in: earlier))
        }
        let laterLowerBound = dayAfter(reviewedRange.upperBound)
        if laterLowerBound <= calculatedRange.upperBound,
           reviewedRange.upperBound < range.upperBound,
           let later = intersection(
               range,
               laterLowerBound...calculatedRange.upperBound
           ) {
            result.append(contentsOf: try await calculated.days(in: later))
        }
        return result.sorted { $0.date < $1.date }
    }

    public func adjacentDay(
        to date: LocalDay,
        direction: LiturgicalDayDirection
    ) async throws -> LiturgicalDay {
        let calendar = Roman1960CalendarMath.gregorianUTC
        guard let value = date.date(in: calendar),
              let adjacent = calendar.date(
                byAdding: .day,
                value: direction == .previous ? -1 : 1,
                to: value
              ) else {
            throw ContentRepositoryError.contentUnavailable(date, nil)
        }
        return try await day(on: LocalDay(adjacent, calendar: calendar))
    }

    public func office(
        on date: LocalDay,
        hour: OfficeHour
    ) async throws -> OfficeDocument {
        let reviewedRange = try await reviewed.coverageRange()
        if reviewedRange.contains(date) {
            return try await reviewed.office(on: date, hour: hour)
        }
        guard parityReport.enablesNativeProvider else {
            throw ContentRepositoryError.dateOutOfCoverage(date, reviewedRange)
        }
        return try await calculated.office(on: date, hour: hour)
    }

    private func calculatedDay(
        on date: LocalDay,
        reviewedRange: ClosedRange<LocalDay>
    ) async throws -> LiturgicalDay {
        guard parityReport.enablesNativeProvider else {
            throw ContentRepositoryError.dateOutOfCoverage(date, reviewedRange)
        }
        return try await calculated.day(on: date)
    }

    private func intersection(
        _ lhs: ClosedRange<LocalDay>,
        _ rhs: ClosedRange<LocalDay>
    ) -> ClosedRange<LocalDay>? {
        let lower = max(lhs.lowerBound, rhs.lowerBound)
        let upper = min(lhs.upperBound, rhs.upperBound)
        return lower <= upper ? lower...upper : nil
    }

    private func dayBefore(_ day: LocalDay) -> LocalDay {
        offset(day, by: -1)
    }

    private func dayAfter(_ day: LocalDay) -> LocalDay {
        offset(day, by: 1)
    }

    private func offset(_ day: LocalDay, by amount: Int) -> LocalDay {
        let calendar = Roman1960CalendarMath.gregorianUTC
        guard let date = day.date(in: calendar),
              let result = calendar.date(byAdding: .day, value: amount, to: date) else {
            preconditionFailure("Invalid Gregorian civil date \(day)")
        }
        return LocalDay(result, calendar: calendar)
    }
}
