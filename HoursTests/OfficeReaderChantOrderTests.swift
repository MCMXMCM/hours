import HoursCore
@testable import Hours
import XCTest

/// The reader folds a score into the prose it replaces, but an ordered office
/// already places every score: no score may be displayed out of that order.
@MainActor
final class OfficeReaderChantOrderTests: XCTestCase {
    private var repository: SQLiteContentRepository!

    override func setUp() async throws {
        repository = try SQLiteContentRepository(
            databaseURL: OfficeTradition.roman1960.databaseURL(),
            expectedTradition: .roman1960
        )
    }

    /// Offices in which a shared phrase once moved a score: the Holy Name
    /// invitatory quoted in a lesson, Sicut erat and the Prime chapter, the
    /// Matins Incipit and a responsory's Gloria Patri, the Tu autem of one
    /// lesson printed in another, a versicle repeating the chapter at None,
    /// the Domine exaudi before the collect, and the conclusion of the dead.
    func testSharedPhrasesDoNotMoveScores() async throws {
        let cases: [(LocalDay, OfficeHour)] = [
            (LocalDay(year: 2026, month: 1, day: 4), .matins),
            (LocalDay(year: 2026, month: 9, day: 28), .prime),
            (LocalDay(year: 2026, month: 1, day: 1), .matins),
            (LocalDay(year: 2026, month: 1, day: 3), .matins),
            (LocalDay(year: 2026, month: 1, day: 15), .none),
            (LocalDay(year: 2026, month: 12, day: 17), .vespers),
            (LocalDay(year: 2026, month: 11, day: 2), .lauds)
        ]
        for (day, hour) in cases {
            let office = try await repository.office(on: day, hour: hour)
            XCTAssertEqual(
                try displacedScores(in: office),
                [],
                "\(day) \(hour)"
            )
        }
    }

    func testHolyNameInvitatoryRemainsBeforeTheHymn() async throws {
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 1, day: 4),
            hour: .matins
        )
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        let firstLesson = try XCTUnwrap(displayed.firstIndex {
            $0.latin.contains("Magnum et mirábile sacraméntum")
        })
        let hymn = try XCTUnwrap(displayed.firstIndex { $0.kind == .hymn })
        XCTAssertGreaterThan(firstLesson, hymn)
    }

    /// A sample of every month across the reviewed window.
    func testScoresKeepTheirOrderAcrossTheReviewedWindow() async throws {
        var failures: [String] = []
        for year in 2025...2036 {
            for month in 1...12 {
                for dayOfMonth in [1, 16] {
                    let day = LocalDay(year: year, month: month, day: dayOfMonth)
                    for hour in OfficeHour.allCases {
                        let office = try await repository.office(on: day, hour: hour)
                        let displaced = try displacedScores(in: office)
                        if !displaced.isEmpty {
                            failures.append("\(day) \(hour): \(displaced)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(failures, [])
    }

    /// Source positions of scores displayed after a later score.
    private func displacedScores(in office: OfficeDocument) throws -> [Int] {
        var positions: [String: [Int]] = [:]
        for (offset, section) in office.sections.enumerated()
        where section.chant != nil {
            positions[section.id, default: []].append(offset)
        }
        let displayed = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )
        var latest = -1
        var displaced: [Int] = []
        for section in displayed where section.chant != nil {
            guard var queue = positions[section.id], !queue.isEmpty else {
                continue
            }
            let position = queue.removeFirst()
            positions[section.id] = queue
            if position < latest { displaced.append(position) }
            latest = max(latest, position)
        }
        return displaced
    }
}
