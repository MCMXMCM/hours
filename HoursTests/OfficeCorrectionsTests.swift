import HoursCore
import XCTest

/// The reviewed corrections in Tools/ContentCompiler/Patches/*-office-corrections.json,
/// read back through the app's repository, which also verifies each digest.
final class OfficeCorrectionsTests: XCTestCase {
    private func repository(_ tradition: OfficeTradition) throws -> SQLiteContentRepository {
        try SQLiteContentRepository(
            databaseURL: tradition.databaseURL(),
            expectedTradition: tradition
        )
    }

    private func text(of office: OfficeDocument) -> String {
        office.sections.map { [$0.title, $0.latin, $0.english ?? ""].joined(separator: "\n") }
            .joined(separator: "\n")
    }

    func testFirstVespersCommemorateTheSundayOfThatYear() async throws {
        let repository = try repository(.roman1960)
        let allSaints = text(of: try await repository.office(
            on: LocalDay(year: 2026, month: 10, day: 31), hour: .vespers
        ))
        XCTAssertTrue(allSaints.contains("Commemoratio Dominica XXIII Post Pentecosten"))
        XCTAssertTrue(allSaints.contains("Absólve, quǽsumus"))
        XCTAssertFalse(allSaints.contains("in tantis perículis"))

        for year in [2027, 2032] {
            let assumption = text(of: try await repository.office(
                on: LocalDay(year: year, month: 8, day: 14), hour: .vespers
            ))
            XCTAssertTrue(assumption.contains("Commemoratio Dominica XIII Post Pentecosten"), "\(year)")
            XCTAssertFalse(assumption.contains("parcéndo"), "\(year)")
        }
    }

    func testConcurrenceOfTheFirstClassKeepsThePrecedingVespers() async throws {
        let repository = try repository(.roman1960)
        for year in [2029, 2035] {
            let vespers = try await repository.office(
                on: LocalDay(year: year, month: 1, day: 6), hour: .vespers
            )
            XCTAssertEqual(vespers.observance?.titleLatin, "In Epiphania Domini", "\(year)")
            XCTAssertEqual(vespers.observance?.eveningContext, .secondVespers, "\(year)")
            XCTAssertFalse(text(of: vespers).contains("Sanctæ Familiæ"), "\(year)")
        }

        let annunciation = try await repository.office(
            on: LocalDay(year: 2028, month: 3, day: 25), hour: .vespers
        )
        XCTAssertEqual(annunciation.observance?.titleLatin, "In Annuntiatione Beatæ Mariæ Virginis")
        XCTAssertTrue(text(of: annunciation).contains("Commemoratio Dominica IV in Quadragesima"))
        XCTAssertFalse(text(of: annunciation).contains("Dominica I Passionis"))

        let joseph = try await repository.office(
            on: LocalDay(year: 2033, month: 3, day: 19), hour: .vespers
        )
        XCTAssertEqual(joseph.observance?.titleLatin, "S. Joseph Sponsi B.M.V. Confessoris")
        XCTAssertTrue(text(of: joseph).contains("Commemoratio Dominica III in Quadragesima"))
        XCTAssertFalse(text(of: joseph).contains("Feria Quarta"))
    }

    /// Corrected at source by Tools/ContentCompiler/Patches/divinum-officium-1960-*.patch.
    func testPatchedDivinumOfficiumRules() async throws {
        let repository = try repository(.roman1960)
        for year in [2028, 2034] {
            let vespers = text(of: try await repository.office(
                on: LocalDay(year: year, month: 12, day: 23), hour: .vespers
            ))
            XCTAssertTrue(vespers.contains("O Emmánuel"), "\(year)")
            XCTAssertFalse(vespers.contains("Excita, quǽsumus"), "\(year)")
        }

        let octaveDay = try await repository.office(
            on: LocalDay(year: 2033, month: 12, day: 30), hour: .lauds
        )
        XCTAssertEqual(octaveDay.observance?.titleLatin, "Diei VI infra Octavam Nativitatis")

        for year in [2030, 2036] {
            let matins = try await repository.office(
                on: LocalDay(year: year, month: 1, day: 12), hour: .matins
            )
            XCTAssertEqual(matins.observance?.titleLatin, "Sanctæ Mariæ Sabbato", "\(year)")
            XCTAssertTrue(text(of: matins).contains("Incipit Epístola prima beáti Pauli Apóstoli ad Corínthios"), "\(year)")
        }

        for year in [2029, 2033, 2035] {
            let vespers = text(of: try await repository.office(
                on: LocalDay(year: year, month: 9, day: 21), hour: .vespers
            ))
            XCTAssertTrue(vespers.contains("Quattuor Temporum Septembris"), "\(year)")
        }
    }

    func testFirstClassDaysAdmitOnlyPrivilegedCommemorations() async throws {
        let repository = try repository(.roman1960)
        for year in [2027, 2032] {
            let lauds = text(of: try await repository.office(
                on: LocalDay(year: year, month: 4, day: 5), hour: .lauds
            ))
            XCTAssertTrue(lauds.contains("Angelo nuntiánte"), "\(year)")
            XCTAssertFalse(lauds.contains("Vincént"), "\(year)")
        }
    }

    func testOrdinaryConclusionsAreSaidOnceWithoutPaschalAlleluia() async throws {
        let repository = try repository(.roman1960)
        let purification = text(of: try await repository.office(
            on: LocalDay(year: 2025, month: 2, day: 1), hour: .vespers
        ))
        XCTAssertFalse(purification.contains("Benedicámus Dómino, allelúia"))

        let compline = try await repository.office(
            on: LocalDay(year: 2026, month: 1, day: 28), hour: .compline
        )
        XCTAssertEqual(
            compline.sections.filter { $0.latin.contains("Benedícat et custódiat nos") }.count,
            1
        )
    }

    func testTitlesUseTheirLatinCases() async throws {
        for tradition in OfficeTradition.allCases {
            let repository = try repository(tradition)
            let michael = try await repository.day(on: LocalDay(year: 2026, month: 9, day: 29))
            XCTAssertEqual(michael.titleLatin, "In Dedicatione S. Michaëlis Archangeli", tradition.title)
            let jerome = try await repository.day(on: LocalDay(year: 2026, month: 9, day: 30))
            XCTAssertEqual(
                jerome.titleLatin,
                "S. Hieronymi Presbyteri Confessoris et Ecclesiæ Doctoris",
                tradition.title
            )
        }
        let joseph = try await repository(.roman1954).day(on: LocalDay(year: 2026, month: 4, day: 22))
        XCTAssertEqual(
            joseph.titleLatin,
            "Solemnitas S. Joseph Sponsi B.M.V. Confessoris et Ecclesiæ universalis Patroni"
        )
    }

    func testEnglishTitlesNameTheirOwnWeek() async throws {
        let repository = try repository(.roman1960)
        let sunday = try await repository.office(
            on: LocalDay(year: 2025, month: 7, day: 27), hour: .lauds
        )
        XCTAssertEqual(sunday.observance?.titleLatin, "Dominica VII Post Pentecosten")
        XCTAssertEqual(sunday.observance?.titleEnglish, "the Seventh Sunday after Pentecost")
        let easter = try await repository.office(
            on: LocalDay(year: 2025, month: 5, day: 25), hour: .lauds
        )
        XCTAssertEqual(easter.observance?.titleEnglish, "the Fifth Sunday after Easter")
    }
}
