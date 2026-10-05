@testable import Hours
import HoursCore
import XCTest

@MainActor
final class HomeHeaderPresentationTests: XCTestCase {
    func testFirstVespersKeepsCivilDayAsPrimaryTitle() {
        let day = wenceslaus
        let office = eveningOffice(
            hour: .vespers,
            observanceID: "michaelmas",
            titleLatin: "In Dedicatione S. Michaëlis Archangelis",
            rank: .firstClass,
            eveningContext: .firstVespers
        )

        let presentation = HomeHeaderPresentation(
            day: day,
            office: office
        )

        XCTAssertEqual(presentation.titleLatin, day.titleLatin)
        XCTAssertEqual(presentation.rank, .thirdClass)
        XCTAssertEqual(
            presentation.officeContext,
            "First Vespers · In Dedicatione S. Michaëlis Archangelis"
        )
    }

    func testComplineExplainsThatItFollowsFirstVespers() {
        let presentation = HomeHeaderPresentation(
            day: wenceslaus,
            office: eveningOffice(
                hour: .compline,
                observanceID: "michaelmas",
                titleLatin: "In Dedicatione S. Michaëlis Archangelis",
                rank: .firstClass,
                eveningContext: .firstVespers
            )
        )

        XCTAssertEqual(
            presentation.officeContext,
            "After First Vespers · In Dedicatione S. Michaëlis Archangelis"
        )
    }

    func testSecondVespersDoesNotAddRedundantDayContext() {
        let michaelmas = LiturgicalDay(
            date: LocalDay(year: 2026, month: 9, day: 29),
            observanceID: "michaelmas",
            titleLatin: "In Dedicatione S. Michaëlis Archangelis",
            rank: .firstClass,
            season: "Tempus per annum"
        )
        let presentation = HomeHeaderPresentation(
            day: michaelmas,
            office: OfficeDocument(
                id: "2026-09-29-vespers",
                date: michaelmas.date,
                hour: .vespers,
                titleLatin: OfficeHour.vespers.latinTitle,
                contextLabel: michaelmas.titleLatin,
                observance: OfficeObservance(
                    observanceID: michaelmas.observanceID,
                    titleLatin: michaelmas.titleLatin,
                    rank: .firstClass,
                    eveningContext: .secondVespers
                ),
                sections: []
            )
        )

        XCTAssertEqual(presentation.titleLatin, michaelmas.titleLatin)
        XCTAssertNil(presentation.officeContext)
    }

    func testOrdinaryVespersTreatsExpandedOrdoAbbreviationsAsSameDay() {
        let day = LiturgicalDay(
            date: LocalDay(year: 2026, month: 9, day: 1),
            observanceID:
                "perennial/feria-tertia-infra-hebd-xiu-post-octauam-pentecostes-u",
            titleLatin:
                "Feria Tertia infra Hebd XIV post Octavam Pentecostes V.",
            rank: .fourthClass,
            season: ""
        )
        let office = OfficeDocument(
            id: "2026-09-01-vespers",
            date: day.date,
            hour: .vespers,
            titleLatin: OfficeHour.vespers.latinTitle,
            contextLabel:
                "Feria Tertia infra Hebdomadam XIV post Octavam Pentecostes V.",
            observance: OfficeObservance(
                observanceID:
                    "perennial/feria-tertia-infra-hebdomadam-xiu-post-octauam-pentecostes-u",
                titleLatin:
                    "Feria Tertia infra Hebdomadam XIV post Octavam Pentecostes V.",
                rank: .fourthClass,
                eveningContext: .ferialVespers
            ),
            sections: []
        )

        let presentation = HomeHeaderPresentation(day: day, office: office)

        XCTAssertNil(presentation.officeContext)
    }

    func testDaytimeOfficeHasNoAdditionalContext() {
        let presentation = HomeHeaderPresentation(
            day: wenceslaus,
            office: OfficeDocument(
                id: "2026-09-28-sext",
                date: wenceslaus.date,
                hour: .sext,
                titleLatin: OfficeHour.sext.latinTitle,
                contextLabel: wenceslaus.titleLatin,
                observance: OfficeObservance(
                    observanceID: wenceslaus.observanceID,
                    titleLatin: wenceslaus.titleLatin,
                    rank: .thirdClass
                ),
                sections: []
            )
        )

        XCTAssertNil(presentation.officeContext)
    }

    private var wenceslaus: LiturgicalDay {
        LiturgicalDay(
            date: LocalDay(year: 2026, month: 9, day: 28),
            observanceID: "wenceslaus",
            titleLatin: "S. Wenceslai Ducis et Martyris",
            rank: .thirdClass,
            season: "Tempus per annum"
        )
    }

    private func eveningOffice(
        hour: OfficeHour,
        observanceID: String,
        titleLatin: String,
        rank: LiturgicalRank,
        eveningContext: EveningContext
    ) -> OfficeDocument {
        OfficeDocument(
            id: "2026-09-28-\(hour.rawValue)",
            date: wenceslaus.date,
            hour: hour,
            titleLatin: hour.latinTitle,
            contextLabel: titleLatin,
            observance: OfficeObservance(
                observanceID: observanceID,
                titleLatin: titleLatin,
                rank: rank,
                eveningContext: eveningContext
            ),
            sections: []
        )
    }
}
