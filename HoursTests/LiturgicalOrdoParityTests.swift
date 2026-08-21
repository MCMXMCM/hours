import XCTest
@testable import HoursCore

final class LiturgicalOrdoParityTests: XCTestCase {
    func testParityValidatorComparesEveryCanonicalHourLocally() async throws {
        let date = LocalDay(year: 2026, month: 8, day: 20)
        let reviewed = repository(for: [date])
        let calculated = repository(for: [date])

        let report = try await LiturgicalOrdoParityValidator.validate(
            reviewed: reviewed,
            calculated: calculated,
            range: date...date,
            calendarEdgeCasesPassed: true
        )

        XCTAssertEqual(report.expectedOfficeCount, 8)
        XCTAssertEqual(report.matchingOfficeCount, 8)
        XCTAssertTrue(report.calendarEdgeCasesPassed)
        XCTAssertFalse(report.enablesNativeProvider)
    }

    func testParityValidatorRejectsOneChangedOffice() async throws {
        let date = LocalDay(year: 2026, month: 8, day: 20)
        let reviewed = repository(for: [date])
        let calculated = repository(
            for: [date],
            changedHour: .vespers
        )

        let report = try await LiturgicalOrdoParityValidator.validate(
            reviewed: reviewed,
            calculated: calculated,
            range: date...date,
            calendarEdgeCasesPassed: true
        )

        XCTAssertEqual(report.expectedOfficeCount, 8)
        XCTAssertEqual(report.matchingOfficeCount, 7)
    }

    func testGatedProviderCannotWidenCoverageBeforeFullParity() async throws {
        let reviewedDate = LocalDay(year: 2100, month: 12, day: 31)
        let futureDate = LocalDay(year: 2101, month: 1, day: 1)
        let provider = ParityGatedLiturgicalOrdoProvider(
            reviewed: repository(for: [reviewedDate]),
            calculated: repository(for: [reviewedDate, futureDate]),
            parityReport: LiturgicalOrdoParityReport(
                expectedOfficeCount: 406_152,
                matchingOfficeCount: 406_151,
                calendarEdgeCasesPassed: true
            )
        )

        let coverage = try await provider.coverageRange()
        XCTAssertEqual(coverage, reviewedDate...reviewedDate)
        do {
            _ = try await provider.day(on: futureDate)
            XCTFail("A partial parity report widened production coverage")
        } catch let error as ContentRepositoryError {
            XCTAssertEqual(
                error,
                .dateOutOfCoverage(futureDate, reviewedDate...reviewedDate)
            )
        }
    }

    func testGatedProviderUsesCalculatedDatesOnlyAfterFullParity() async throws {
        let reviewedDate = LocalDay(year: 2100, month: 12, day: 31)
        let futureDate = LocalDay(year: 2101, month: 1, day: 1)
        let provider = ParityGatedLiturgicalOrdoProvider(
            reviewed: repository(for: [reviewedDate]),
            calculated: repository(for: [reviewedDate, futureDate]),
            parityReport: LiturgicalOrdoParityReport(
                expectedOfficeCount: 406_152,
                matchingOfficeCount: 406_152,
                calendarEdgeCasesPassed: true
            )
        )

        let coverage = try await provider.coverageRange()
        let day = try await provider.day(on: futureDate)
        let office = try await provider.office(on: futureDate, hour: .prime)
        XCTAssertEqual(coverage, reviewedDate...futureDate)
        XCTAssertEqual(day.date, futureDate)
        XCTAssertEqual(office.date, futureDate)
    }

    private func repository(
        for dates: [LocalDay],
        changedHour: OfficeHour? = nil
    ) -> InMemoryContentRepository {
        InMemoryContentRepository(
            days: dates.map(day),
            offices: dates.flatMap { date in
                OfficeHour.allCases.map { hour in
                    office(
                        date: date,
                        hour: hour,
                        text: hour == changedHour ? "Mutated text" : "Text"
                    )
                }
            }
        )
    }

    private func day(_ date: LocalDay) -> LiturgicalDay {
        LiturgicalDay(
            date: date,
            observanceID: "temporal/feria",
            titleLatin: "Feria",
            rank: .fourthClass,
            color: .green,
            season: "Per annum"
        )
    }

    private func office(
        date: LocalDay,
        hour: OfficeHour,
        text: String
    ) -> OfficeDocument {
        OfficeDocument(
            id: "\(date)-\(hour.rawValue)",
            date: date,
            hour: hour,
            titleLatin: hour.latinTitle,
            titleEnglish: hour.englishTitle,
            contextLabel: "Feria",
            observance: OfficeObservance(
                observanceID: "temporal/feria",
                titleLatin: "Feria",
                rank: .fourthClass,
                color: .green,
                season: "Per annum"
            ),
            sections: [
                OfficeSection(
                    id: "section-0",
                    kind: .prayer,
                    title: "Oratio",
                    latin: text
                )
            ]
        )
    }
}
