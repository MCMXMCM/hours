import XCTest
@testable import HoursCore

final class ContentPerformanceBudgetTests: XCTestCase {
    func testBundled2026PackStaysWithinSizeBudget() throws {
        let url = try bundledDatabaseURL()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertLessThanOrEqual(size, ContentPerformanceBudgets.development2026PackBytes)
    }

    func testColdRepositoryOpenAndOfficeReadStayWithinBudgets() async throws {
        let url = try bundledDatabaseURL()

        let openStart = ContinuousClock.now
        let repository = try SQLiteContentRepository(databaseURL: url)
        let openElapsed = openStart.duration(to: .now).seconds
        XCTAssertLessThanOrEqual(
            openElapsed,
            ContentPerformanceBudgets.coldRepositoryOpenSeconds
        )

        let readStart = ContinuousClock.now
        _ = try await repository.office(
            on: LocalDay(year: 2026, month: 12, day: 8),
            hour: .vespers
        )
        let readElapsed = readStart.duration(to: .now).seconds
        XCTAssertLessThanOrEqual(
            readElapsed,
            ContentPerformanceBudgets.officeReadSeconds
        )
    }

    func testRepresentativeOfficeMemoryMetric() throws {
        let url = try bundledDatabaseURL()
        measure(metrics: [XCTMemoryMetric()]) {
            autoreleasepool {
                _ = try? SQLiteContentRepository(databaseURL: url)
            }
        }
    }

    private func bundledDatabaseURL() throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            )
                ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
