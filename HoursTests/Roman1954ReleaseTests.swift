import Foundation
@testable import HoursCore
import XCTest

final class Roman1954ReleaseTests: XCTestCase {
    func testCollatedPrimeHymnsAndPaschalAntiphonSurviveSharedStorage() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL(), expectedTradition: .roman1954)
        for (month, day, mode) in [(1, 14, "2"), (1, 18, "8"), (2, 3, "6")] {
            let office = try await repository.office(on: LocalDay(year: 2025, month: month, day: day), hour: .prime)
            let hymn = try XCTUnwrap(office.sections.first { $0.latin.hasPrefix("Jam lucis") })
            let chant = try XCTUnwrap(hymn.chant)
            XCTAssertEqual(chant.mode, mode)
            XCTAssertTrue(hymn.latin.contains("abscésserit"))
            XCTAssertTrue(hymn.english?.contains("light") == true)
            XCTAssertTrue(chant.gabc.contains("ná("))
            XCTAssertFalse(chant.gabc.contains("cá("))
        }
        let compline = try await repository.office(on: LocalDay(year: 2025, month: 4, day: 26), hour: .compline)
        let antiphon = try XCTUnwrap(compline.sections.first { $0.latin.hasPrefix("Ant. Salva nos, Dómine") })
        let chant = try XCTUnwrap(antiphon.chant)
        XCTAssertTrue(antiphon.latin.hasSuffix("allelúja."))
        XCTAssertTrue(antiphon.english?.hasSuffix("alleluia.") == true)
        XCTAssertTrue(chant.gabc.contains("Al(g)le(gf)lú(e.)ja.(e.)"))
        XCTAssertFalse(chant.gabc.contains("T. P."))
    }

    func testPublicPaterAndPrimeResponsesSurviveSharedStorage() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL(), expectedTradition: .roman1954)
        let matins = try await repository.office(on: LocalDay(year: 2025, month: 1, day: 1), hour: .matins)
        let conclusions = matins.sections.filter { $0.latin.hasPrefix("℣. Et ne nos indúcas") }
        XCTAssertEqual(conclusions.count, 3)
        XCTAssertTrue(conclusions.allSatisfy { $0.chant != nil && $0.english?.contains("But deliver us from evil") == true })
        let silent = matins.sections.filter { $0.latin.contains("Panem nostrum") }
        XCTAssertEqual(silent.count, 5)
        XCTAssertTrue(silent.allSatisfy { $0.chant == nil })
        let prime = try await repository.office(on: LocalDay(year: 2025, month: 1, day: 14), hour: .prime)
        let response = try XCTUnwrap(prime.sections.first { $0.latin.hasPrefix("℟.br. Christe, Fili") })
        XCTAssertNotNil(response.chant)
        XCTAssertEqual(response.latin.components(separatedBy: "Christe, Fili Dei vivi").count - 1, 3)
        let invocations = prime.sections.filter { $0.chant?.gabc.contains("De(h)us(h) in(h) ad(h)ju(h)tó") == true }
        XCTAssertEqual(invocations.count, 3)
    }

    func testRomanVexillaKeepsTheKneelingDirectionBetweenItsScores() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let office = try await repository.office(on: LocalDay(year: 2025, month: 4, day: 13), hour: .vespers)
        let start = try XCTUnwrap(office.sections.firstIndex { $0.latin.hasPrefix("Vexílla Regis") })
        let first = office.sections[start], direction = office.sections[start + 1], last = office.sections[start + 2]
        XCTAssertNotNil(first.chant)
        XCTAssertTrue(first.latin.contains("Qua Vita mortem pértulit"))
        XCTAssertTrue(first.latin.contains("Tulítque prædam tártari"))
        XCTAssertEqual(direction.latin, "Sequens stropha dicitur flexis genibus.")
        XCTAssertTrue(direction.english?.contains("bended knee") == true)
        XCTAssertNil(direction.chant)
        XCTAssertNotNil(last.chant)
        XCTAssertTrue(last.latin.hasPrefix("O Crux"))
        XCTAssertTrue(last.latin.contains("Te, fons salútis"))
    }

    func testMartyrologyRepairsAppearInEveryYearWithoutLosingTheVigil() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        for year in 2025...2036 {
            let februaryDay = 22
            let prime = try await repository.office(on: LocalDay(year: year, month: 2, day: februaryDay), hour: .prime)
            let english = prime.sections.compactMap(\.english).joined(separator: "\n")
            XCTAssertTrue(english.contains("At Smyrna, the birthday of Saint Polycarp"), "\(year)")
            XCTAssertTrue(english.contains("holy Priest Polycarp"), "\(year)")
            let christmas = try await repository.office(on: LocalDay(year: year, month: 12, day: 24), hour: .prime)
            let text = christmas.sections.compactMap(\.english).joined(separator: "\n")
            XCTAssertTrue(text.contains("fifth Kalends of February"))
            XCTAssertFalse(text.contains("last day of January"))
            let nolasco = try XCTUnwrap(text.range(of: "At Barcelona in Spain"))
            let eugenia = try XCTUnwrap(text.range(of: "At Rome, in the Apronian"))
            XCTAssertLessThan(nolasco.lowerBound, eugenia.lowerBound)
        }
    }
    func testHolyThursdayAndGoodFridayVespersAreRecitedWithoutChant() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let dates = ["2025-04-17", "2026-04-02", "2027-03-25", "2028-04-13",
            "2029-03-29", "2030-04-18", "2031-04-10", "2032-03-25",
            "2033-04-14", "2034-04-06", "2035-03-22", "2036-04-10"]
        for date in dates {
            let parts = date.split(separator: "-").compactMap { Int($0) }
            for offset in 0...1 {
                let office = try await repository.office(on: LocalDay(year: parts[0], month: parts[1], day: parts[2] + offset), hour: .vespers)
                XCTAssertTrue(office.sections.allSatisfy { $0.chant == nil }, date)
                let latin = office.sections.map(\.latin).joined(separator: "\n")
                XCTAssertTrue(latin.contains("Cálicem"))
                XCTAssertTrue(latin.contains("Magníficat"))
                XCTAssertTrue(latin.contains("Réspice, quǽsumus"))
                XCTAssertTrue(office.sections.allSatisfy { !($0.english ?? "").isEmpty })
            }
        }
    }

}
