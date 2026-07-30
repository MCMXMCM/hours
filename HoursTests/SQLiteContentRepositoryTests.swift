import XCTest
@testable import HoursCore

final class SQLiteContentRepositoryTests: XCTestCase {
    func testBundledDevelopmentCorpusLoadsOffline() async throws {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "base-office", withExtension: "sqlite", subdirectory: "Resources")
            ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let databaseURL = try XCTUnwrap(url)
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)

        let days = try await repository.availableDays()
        XCTAssertEqual(days.count, 365)
        XCTAssertEqual(days.first?.date, LocalDay(year: 2026, month: 1, day: 1))
        XCTAssertEqual(days.last?.date, LocalDay(year: 2026, month: 12, day: 31))

        let pilotDay = LocalDay(year: 2026, month: 7, day: 23)
        let offices = try await OfficeHour.allCases.asyncMap {
            try await repository.office(on: pilotDay, hour: $0)
        }
        XCTAssertEqual(offices.map(\.hour), OfficeHour.allCases)
        XCTAssertTrue(offices.allSatisfy { !$0.playableScores.isEmpty })

        let prime = try await repository.office(on: pilotDay, hour: .prime)
        let terce = try await repository.office(on: pilotDay, hour: .terce)
        let vespers = try await repository.office(on: pilotDay, hour: .vespers)
        let compline = try await repository.office(on: pilotDay, hour: .compline)
        XCTAssertFalse(prime.playableScores.isEmpty)
        XCTAssertFalse(terce.playableScores.isEmpty)
        XCTAssertNotNil(prime.sections.first?.chant)
        XCTAssertNotNil(terce.sections.first?.chant)
        XCTAssertEqual(vespers.hour, .vespers)
        XCTAssertEqual(compline.hour, .compline)
        XCTAssertFalse(vespers.playableScores.isEmpty)
        XCTAssertTrue(vespers.playableScores.allSatisfy { !$0.timeline.events.isEmpty })

        let sourceRubrics = offices
            .flatMap(\.sections)
            .filter { section in
                guard let rubric = section.rubric,
                      let collection = section.chant?.provenance.collection else {
                    return false
                }
                return rubric == collection || rubric.hasPrefix("\(collection) · ")
            }
        XCTAssertFalse(sourceRubrics.isEmpty)
        XCTAssertTrue(sourceRubrics.allSatisfy { $0.userFacingRubric == nil })
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
