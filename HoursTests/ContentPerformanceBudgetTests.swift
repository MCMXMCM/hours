import Darwin
import XCTest
@testable import Hours
@testable import HoursCore

@MainActor
final class ContentPerformanceBudgetTests: XCTestCase {
    func testBundledCorpusStaysWithinItsDeclaredSizeBudget() async throws {
        let url = try bundledDatabaseURL()
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let size = try XCTUnwrap(
            attributes[.size] as? NSNumber
        ).intValue
        let coverage = try await SQLiteContentRepository(
            databaseURL: url
        ).coverageRange()
        let inclusiveYearCount = coverage.upperBound.year
            - coverage.lowerBound.year + 1
        let isReviewedWindow = inclusiveYearCount == 12
            && coverage.lowerBound.month == 1
            && coverage.lowerBound.day == 1
            && coverage.upperBound.month == 12
            && coverage.upperBound.day == 31
        let budget = isReviewedWindow
            ? ContentPerformanceBudgets.reviewedWindowReleasePackBytes
            : ContentPerformanceBudgets.perennialParityPackBytes

        XCTAssertTrue(isReviewedWindow)
        XCTAssertLessThanOrEqual(size, budget)
    }

    func testCorpusStartupAndAvailableDaysStayWithinBudgets() async throws {
        let url = try bundledDatabaseURL()
        let startupStart = ContinuousClock.now

        let openStart = ContinuousClock.now
        let repository = try SQLiteContentRepository(databaseURL: url)
        let openElapsed = openStart.duration(to: .now).seconds
        XCTAssertLessThanOrEqual(
            openElapsed,
            ContentPerformanceBudgets.coldRepositoryOpenSeconds
        )

        let daysStart = ContinuousClock.now
        let days = try await repository.availableDays()
        let daysElapsed = daysStart.duration(to: .now).seconds
        XCTAssertEqual(days.count, 4_383)
        XCTAssertLessThanOrEqual(
            daysElapsed,
            ContentPerformanceBudgets.availableDaysReadSeconds
        )

        _ = try JSONEncoder().encode(
            HoursLiturgicalCalendarSnapshot(days: days)
        )
        let startupElapsed = startupStart.duration(to: .now).seconds
        XCTAssertLessThanOrEqual(
            startupElapsed,
            ContentPerformanceBudgets.corpusStartupSeconds
        )
    }

    func testRepresentativeAndLargestOfficeReadsStayWithinBudget() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )

        let representativeStart = ContinuousClock.now
        let representative = try await repository.office(
            on: LocalDay(year: 2026, month: 12, day: 8),
            hour: .vespers
        )
        let representativeElapsed = representativeStart
            .duration(to: .now).seconds
        XCTAssertFalse(representative.sections.isEmpty)
        XCTAssertLessThanOrEqual(
            representativeElapsed,
            ContentPerformanceBudgets.officeReadSeconds
        )

        let largestStart = ContinuousClock.now
        let largest = try await repository.office(
            on: LocalDay(year: 2025, month: 12, day: 25),
            hour: .matins
        )
        let largestElapsed = largestStart.duration(to: .now).seconds
        XCTAssertEqual(largest.sections.count, 196)
        XCTAssertLessThanOrEqual(
            largestElapsed,
            ContentPerformanceBudgets.officeReadSeconds
        )
    }

    func testOfflineContentAndTitleSearchStayWithinBudgets() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )

        let searchStart = ContinuousClock.now
        let results = try await repository.searchHits(
            query: "Salve Regina",
            language: .latin,
            kind: nil,
            limit: 50
        )
        let searchElapsed = searchStart.duration(to: .now).seconds
        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThanOrEqual(
            searchElapsed,
            ContentPerformanceBudgets.searchSeconds
        )

        let usageRange = LocalDay(year: 2026, month: 1, day: 1)...LocalDay(
            year: 2026,
            month: 12,
            day: 31
        )
        let coldTitleStart = ContinuousClock.now
        let coldTitles = try await repository.searchOfficeTitles(
            query: "Dominica",
            language: .latin,
            usageRange: usageRange
        )
        let coldTitleElapsed = coldTitleStart.duration(to: .now).seconds
        XCTAssertFalse(coldTitles.isEmpty)
        XCTAssertLessThanOrEqual(
            coldTitleElapsed,
            ContentPerformanceBudgets.titleSearchSeconds
        )

        let warmTitleStart = ContinuousClock.now
        let warmTitles = try await repository.searchOfficeTitles(
            query: "Sancti",
            language: .latin,
            usageRange: usageRange
        )
        let warmTitleElapsed = warmTitleStart.duration(to: .now).seconds
        XCTAssertFalse(warmTitles.isEmpty)
        XCTAssertLessThanOrEqual(
            warmTitleElapsed,
            ContentPerformanceBudgets.titleSearchSeconds
        )
        let metrics = await repository.cacheMetricsForTesting()
        XCTAssertGreaterThan(metrics.recipeHeaderHits, 0)
    }

    func testRepresentativeContentPhysicalFootprintStaysWithinBudget() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )
        let days = try await repository.availableDays()
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 12, day: 8),
            hour: .vespers
        )
        let presentation = try OfficeReaderPresentation.prepare(
            office: office
        )
        await GregorianLayoutCache.shared.resetForTesting()
        let preparedScores = await GregorianScorePreparer.prepare(
            scores: presentation.scores,
            width: 390,
            metrics: GregorianLayoutMetrics()
        )

        XCTAssertEqual(days.count, 4_383)
        XCTAssertFalse(office.sections.isEmpty)
        XCTAssertEqual(preparedScores.count, presentation.scores.count)

        let physicalFootprint = try withExtendedLifetime(
            (days, office, presentation, preparedScores)
        ) {
            try currentPhysicalFootprint()
        }
        XCTAssertGreaterThan(physicalFootprint, 0)
        XCTAssertLessThanOrEqual(
            physicalFootprint,
            UInt64(ContentPerformanceBudgets.residentMemoryBytes)
        )
    }

    private func bundledDatabaseURL() throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite"
            )
        )
    }

    private func currentPhysicalFootprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw ContentRepositoryError.databaseUnavailable(
                "Unable to read process physical footprint (Mach error \(result))."
            )
        }
        return info.phys_footprint
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
