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
        // Each run opens the repository afresh, so its own caches are cold;
        // the best of three runs keeps a busy test machine from failing the
        // budgets.
        var openElapsed = Double.infinity
        var daysElapsed = Double.infinity
        var startupElapsed = Double.infinity
        for _ in 0..<3 {
            let startupStart = ContinuousClock.now

            let openStart = ContinuousClock.now
            let repository = try SQLiteContentRepository(databaseURL: url)
            openElapsed = min(openElapsed, openStart.duration(to: .now).seconds)

            let daysStart = ContinuousClock.now
            let days = try await repository.availableDays()
            daysElapsed = min(daysElapsed, daysStart.duration(to: .now).seconds)
            XCTAssertEqual(days.count, 4_383)

            _ = try JSONEncoder().encode(
                HoursLiturgicalCalendarSnapshot(days: days)
            )
            startupElapsed = min(startupElapsed, startupStart.duration(to: .now).seconds)
        }
        XCTAssertLessThanOrEqual(
            openElapsed,
            ContentPerformanceBudgets.coldRepositoryOpenSeconds
        )
        XCTAssertLessThanOrEqual(
            daysElapsed,
            ContentPerformanceBudgets.availableDaysReadSeconds
        )
        XCTAssertLessThanOrEqual(
            startupElapsed,
            ContentPerformanceBudgets.corpusStartupSeconds
        )
    }

    func testOfflineContentAndTitleSearchStayWithinBudgets() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )

        // A repeatable query is timed at its best of three runs, so a busy
        // test machine does not fail the budget.
        var results: [LiturgicalSearchHit] = []
        let searchElapsed = try await bestElapsed {
            results = try await repository.searchHits(
                query: "Salve Regina",
                language: .latin,
                kind: nil,
                limit: 50
            )
        }
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
        // The cold title search runs on a freshly opened repository each
        // time, so its title cache is cold in every run.
        var coldTitles: [LiturgicalUsageContext] = []
        let coldTitleElapsed = try await bestElapsed {
            let fresh = try SQLiteContentRepository(databaseURL: bundledDatabaseURL())
            coldTitles = try await fresh.searchOfficeTitles(
                query: "Dominica",
                language: .latin,
                usageRange: usageRange
            )
        }
        XCTAssertFalse(coldTitles.isEmpty)
        XCTAssertLessThanOrEqual(
            coldTitleElapsed,
            ContentPerformanceBudgets.titleSearchSeconds
        )

        // Warm the shared repository's title cache, then time a search on it.
        _ = try await repository.searchOfficeTitles(
            query: "Dominica",
            language: .latin,
            usageRange: usageRange
        )
        var warmTitles: [LiturgicalUsageContext] = []
        let warmTitleElapsed = try await bestElapsed {
            warmTitles = try await repository.searchOfficeTitles(
                query: "Sancti",
                language: .latin,
                usageRange: usageRange
            )
        }
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

    private func bestElapsed(
        of runs: Int = 3,
        _ operation: () async throws -> Void
    ) async rethrows -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try await operation()
            best = min(best, start.duration(to: .now).seconds)
        }
        return best
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
