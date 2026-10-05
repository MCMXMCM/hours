import Foundation
@testable import HoursCore
import XCTest

final class Roman1954CorpusTests: XCTestCase {
    func testBundled1954CalendarHasAllEightHoursAndSourceIdentity() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL(), expectedTradition: .roman1954)
        let days = try await repository.availableDays()
        XCTAssertEqual(days.count, 4_383)
        XCTAssertEqual(days.first?.date, LocalDay(year: 2025, month: 1, day: 1))
        XCTAssertEqual(days.last?.date, LocalDay(year: 2036, month: 12, day: 31))
        let dates = [
            LocalDay(year: 2025, month: 1, day: 1),
            LocalDay(year: 2026, month: 1, day: 13),
            LocalDay(year: 2026, month: 4, day: 2),
            LocalDay(year: 2026, month: 4, day: 3),
            LocalDay(year: 2026, month: 4, day: 4),
            LocalDay(year: 2026, month: 4, day: 5),
            LocalDay(year: 2026, month: 5, day: 1),
            LocalDay(year: 2026, month: 9, day: 6),
            LocalDay(year: 2026, month: 9, day: 7),
            LocalDay(year: 2026, month: 11, day: 2),
            LocalDay(year: 2027, month: 5, day: 18),
            LocalDay(year: 2028, month: 2, day: 29),
            LocalDay(year: 2036, month: 12, day: 31)
        ]
        for date in dates {
            for hour in OfficeHour.allCases {
                let office = try await repository.office(on: date, hour: hour)
                XCTAssertEqual(office.date, date)
                XCTAssertEqual(office.hour, hour)
                XCTAssertEqual(office.format, .sourceOrdered)
                XCTAssertTrue(office.id.hasPrefix("roman1954:"))
                XCTAssertTrue(office.sourceVersion.contains("Divino Afflatu - 1954"))
                XCTAssertFalse(office.sections.isEmpty)
                XCTAssertNoThrow(try VisibleContentDigest.validate(office))
                XCTAssertTrue(office.sections.allSatisfy { !$0.latin.isEmpty })
                XCTAssertNil(office.observance?.rank)
                for score in office.sections.compactMap(\.chant) {
                    XCTAssertTrue(score.id.hasPrefix("roman1954-"))
                    XCTAssertEqual(score.reviewStatus, .sourceTranscription)
                }
            }
        }
    }

    func test1954HasItsOwnFeastsNineLessonMatinsAndFirstVespers() async throws {
        let earlier = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let later = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1960.databaseURL())
        for (date, title) in [
            (LocalDay(year: 2026, month: 1, day: 13), "In Octava Epiphaniæ"),
            (LocalDay(year: 2026, month: 5, day: 1), "Ss. Philippi et Jacobi Apostolorum")
        ] {
            let first = try await earlier.day(on: date)
            let second = try await later.day(on: date)
            XCTAssertEqual(first.titleLatin, title)
            XCTAssertNotEqual(first.titleLatin, second.titleLatin)
            XCTAssertNotNil(first.sourceRank)
            XCTAssertNil(first.rank)
        }
        let matins = try await earlier.office(on: LocalDay(year: 2026, month: 9, day: 6), hour: .matins)
        let titles = Set(matins.sections.map(\.title))
        for number in 1...9 { XCTAssertTrue(titles.contains("Lectio \(number)")) }
        XCTAssertFalse(titles.contains("Lectio 10"))
        let vespers = try await earlier.office(on: LocalDay(year: 2026, month: 9, day: 7), hour: .vespers)
        XCTAssertEqual(vespers.observance?.titleLatin, "In Nativitate Beatæ Mariæ Virginis")
        XCTAssertEqual(vespers.observance?.sourceRank, "Duplex II. classis")
        XCTAssertEqual(vespers.observance?.eveningContext, .firstVespers)
        XCTAssertTrue(vespers.sections.allSatisfy { !($0.english ?? "").isEmpty })
        let hits = try await earlier.searchHits(query: "blessing", language: .english, kind: nil, limit: 10)
        XCTAssertFalse(hits.isEmpty)
    }
    func testCorrectedOfficesAndCommemorationsInSharedBundle() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL(), expectedTradition: .roman1954)
        for year in 2025...2036 {
            let day = [2025, 2031, 2036].contains(year) ? 2 : 1
            let office = try await repository.office(on: LocalDay(year: year, month: 11, day: day), hour: .vespers)
            let start = try XCTUnwrap(office.sections.firstIndex { $0.title == "Vesperæ Defunctorum" })
            XCTAssertGreaterThan(start, 0)
            XCTAssertTrue(office.sections[start].latin.hasPrefix("Ant. Placébo Dómino"))
            let continuation = office.sections[start...].map(\.latin).joined(separator: "\n")
            for psalm in [114, 119, 120, 129, 137] { XCTAssertTrue(continuation.contains("Psalmus \(psalm) ")) }
            XCTAssertTrue(continuation.contains("Fidélium, Deus, ómnium Cónditor et Redémptor"))
            XCTAssertFalse(continuation.contains("Ave María"))
            XCTAssertNoThrow(try VisibleContentDigest.validate(office))
        }
        for year in [2027, 2032] {
            let office = try await repository.office(on: LocalDay(year: year, month: 5, day: 18), hour: .matins)
            let text = office.sections.map(\.latin).joined(separator: "\n")
            XCTAssertTrue(text.contains("Jam Christus astra ascénderat"))
            XCTAssertFalse(text.contains("{:H-"))
            XCTAssertGreaterThan(office.sections.compactMap(\.chant).count, 10)
        }
        let date = LocalDay(year: 2026, month: 3, day: 25)
        let day = try await repository.day(on: date)
        XCTAssertEqual(day.commemorations.map(\.titleLatin), ["Feria Quarta infra Hebdomadam Passionis"])
        let compline = try await repository.office(on: LocalDay(year: 2026, month: 9, day: 8), hour: .compline)
        let chapter = try XCTUnwrap(compline.sections.first { $0.latin.contains("Tu autem in nobis") })
        XCTAssertTrue(try XCTUnwrap(chapter.chant).gabc.contains("sanc(h)tum(h)"))
    }

    func testTenebraeResponsesAndPassiontideRubricsSurviveSharedStorage() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL(), expectedTradition: .roman1954)
        for day in 17...19 {
            let office = try await repository.office(on: LocalDay(year: 2025, month: 4, day: day), hour: .matins)
            let responses = office.sections.filter { $0.kind == .responsory && $0.chant != nil }
            XCTAssertEqual(responses.count, 9)
            let omissions = responses.filter { $0.rubric == "Gloria omittitur" }
            XCTAssertEqual(omissions.count, 3)
            XCTAssertTrue(omissions.allSatisfy { !($0.rubricEnglish ?? "").isEmpty })
            XCTAssertNoThrow(try VisibleContentDigest.validate(office))
        }
        for (hour, incipit) in [(OfficeHour.terce, "Erue a framea"), (.sext, "De ore leonis"), (.none, "Ne perdas cum impiis"), (.compline, "In manus tuas")] {
            let office = try await repository.office(on: LocalDay(year: 2025, month: 4, day: 13), hour: hour)
            let response = try XCTUnwrap(office.sections.first { $0.chant?.incipit == incipit })
            XCTAssertEqual(response.rubric, "Gloria omittitur")
            XCTAssertEqual(response.rubricEnglish, "omit Glory be")
            XCTAssertFalse(try XCTUnwrap(response.chant).gabc.contains("Gló("))
        }
    }

    func testSeptember10ComplineMusicSurvivesBundlingAndNativeLayout() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let office = try await repository.office(on: LocalDay(year: 2026, month: 9, day: 10), hour: .compline)
        XCTAssertNoThrow(try VisibleContentDigest.validate(office))
        XCTAssertEqual(office.sections.compactMap(\.chant).count, 26)
        for marker in ["70:1 ", "70:13 "] {
            let section = try XCTUnwrap(office.sections.first { $0.latin.contains(marker) })
            XCTAssertEqual(try XCTUnwrap(section.chant).incipit, "70-8G")
        }
        let response = try XCTUnwrap(office.sections.first { $0.chant?.incipit == "In manus tuas" })
        XCTAssertTrue(response.latin.contains("Glória Patri"))
        let snapshots: Set<String> = [
            "1144bce2ae1f5bf989ad9da54ef1793247b85473cac77c2c09ea6a50f0c3d7bf",
            "1c8fa6090b6ba0a7caaa762e28f1eda5c43607f8d8d4d70157a3ef023c494a7a",
            "6e1cbedb529403f45884094945e2139ffb2b4e14cb46dd9b46631dc05e6c211e",
            "5a7e7a456a6cf34f442d8c11966fb8c21a9b1f86b7810ea3d5c8bae50e18eef3"
        ]
        let corrected = office.sections.compactMap(\.chant).filter { snapshots.contains($0.provenance.snapshot) }
        XCTAssertEqual(corrected.count, 4)
        for chant in corrected {
            let score = try GregorianScoreParser.parse(gabc: chant.gabc, timeline: chant.timeline)
            for width in [CGFloat(320), 390, 768] {
                let layout = GregorianEngravingLayoutEngine().layout(score: score, width: width)
                XCTAssertEqual(layout.events.map(\.eventID), score.eventIDs)
                XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
                for line in Dictionary(grouping: layout.neumes, by: \.lineIndex).values {
                    let ordered = line.sorted { $0.hitFrame.minX < $1.hitFrame.minX }
                    for pair in zip(ordered, ordered.dropFirst()) {
                        XCTAssertLessThanOrEqual(pair.0.hitFrame.maxX, pair.1.hitFrame.minX + 0.01)
                    }
                }
            }
        }
    }

}
