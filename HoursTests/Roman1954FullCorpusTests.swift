import Foundation
@testable import HoursCore
import XCTest

final class Roman1954FullCorpusTests: XCTestCase {
    func testEveryAddedOfficeLoadsWithItsDigestAndComplineBlessingNotation() async throws {
        var jobs: [(OfficeTradition, [LocalDay])] = []
        for tradition in [OfficeTradition.roman1954] {
            let repository = try SQLiteContentRepository(databaseURL: tradition.databaseURL(), expectedTradition: tradition)
            let dates = try await repository.availableDays().map(\.date)
            for year in 2025...2036 {
                jobs.append((tradition, dates.filter { $0.year == year }))
            }
        }
        let counts = try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            var cursor = 0
            var checked = 0
            var blessings = 0
            func enqueue() {
                guard cursor < jobs.count else { return }
                let (tradition, dates) = jobs[cursor]
                cursor += 1
                group.addTask {
                    try await Self.validateOffices(tradition: tradition, dates: dates)
                }
            }
            for _ in 0..<4 { enqueue() }
            while let (offices, openings) = try await group.next() {
                checked += offices
                blessings += openings
                print("Validated \(checked)/35,064 added offices through the native repository")
                enqueue()
            }
            return (checked, blessings)
        }
        XCTAssertEqual(counts.0, 35_064)
        XCTAssertEqual(counts.1, 4_347)
    }

    private static func validateOffices(tradition: OfficeTradition, dates: [LocalDay]) async throws -> (Int, Int) {
        let repository = try SQLiteContentRepository(databaseURL: tradition.databaseURL(), expectedTradition: tradition)
        var checked = 0
        var blessings = 0
        for date in dates {
            for hour in OfficeHour.allCases {
                // office(on:hour:) itself validates the visible digest.
                let office = try await repository.office(on: date, hour: hour)
                XCTAssertEqual(office.date, date)
                XCTAssertEqual(office.hour, hour)
                XCTAssertFalse(office.sections.isEmpty)
                for section in office.sections where section.latin.contains("Noctem quiétam") {
                    let score = try XCTUnwrap(section.chant, "Missing blessing notation: \(tradition) \(date) \(hour)")
                    XCTAssertTrue(score.gabc.contains("Noc(h)tem"))
                    XCTAssertFalse(score.timeline.events.isEmpty)
                    XCTAssertTrue(section.english?.contains("quiet night") == true)
                    blessings += 1
                }
                checked += 1
            }
        }
        return (checked, blessings)
    }

}
