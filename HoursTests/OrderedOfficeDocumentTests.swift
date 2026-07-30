import XCTest
@testable import HoursCore

final class OrderedOfficeDocumentTests: XCTestCase {
    func testSwiftDecodesOrderedMatinsVespersAndComplineWithStandaloneRubrics() throws {
        let data = Data(
            """
            [
              {
                "id": "2026-12-08-matins",
                "date": {"year": 2026, "month": 12, "day": 8},
                "hour": "matins",
                "titleLatin": "Ad Matutinum",
                "titleEnglish": "Matins",
                "contextLabel": "In Conceptione Immaculata B. Mariae Virginis",
                "sourceVersion": "Rubrics 1960 - 1960",
                "format": "authoritativeOrdered",
                "visibleContentDigest": "fixture",
                "observance": {
                  "observanceID": "in-conceptione-immaculata",
                  "titleLatin": "In Conceptione Immaculata B. Mariae Virginis",
                  "titleEnglish": "The Immaculate Conception of the Blessed Virgin Mary",
                  "rank": "firstClass",
                  "color": "white",
                  "season": "Advent",
                  "eveningContext": null,
                  "commemorations": []
                },
                "sections": [
                  {
                    "id": "matins-rubric-1",
                    "kind": "rubric",
                    "title": "Rubrica",
                    "rubric": null,
                    "latin": "Absolutio et benedictiones ut in Communi.",
                    "english": null,
                    "chant": null
                  },
                  {
                    "id": "matins-prayer-1",
                    "kind": "prayer",
                    "title": "Oratio",
                    "rubric": "Orémus.",
                    "latin": "Deus, qui per immaculátam Vírginis Conceptiónem.",
                    "english": null,
                    "chant": null
                  }
                ]
              },
              {
                "id": "2026-12-08-vespers",
                "date": {"year": 2026, "month": 12, "day": 8},
                "hour": "vespers",
                "titleLatin": "Ad Vesperas",
                "titleEnglish": "Vespers",
                "contextLabel": "In Conceptione Immaculata B. Mariae Virginis",
                "sourceVersion": "Rubrics 1960 - 1960",
                "format": "authoritativeOrdered",
                "visibleContentDigest": "fixture",
                "observance": {
                  "observanceID": "in-conceptione-immaculata",
                  "titleLatin": "In Conceptione Immaculata B. Mariae Virginis",
                  "titleEnglish": "The Immaculate Conception of the Blessed Virgin Mary",
                  "rank": "firstClass",
                  "color": "white",
                  "season": "Advent",
                  "eveningContext": "secondVespers",
                  "commemorations": []
                },
                "sections": [
                  {
                    "id": "vespers-rubric-1",
                    "kind": "rubric",
                    "title": "Rubrica",
                    "rubric": null,
                    "latin": "Antiphona dicitur ante et post psalmum.",
                    "english": null,
                    "chant": null
                  },
                  {
                    "id": "vespers-prayer-1",
                    "kind": "prayer",
                    "title": "Oratio",
                    "rubric": "Orémus.",
                    "latin": "Deus, qui per immaculátam Vírginis Conceptiónem.",
                    "english": null,
                    "chant": null
                  }
                ]
              },
              {
                "id": "2026-12-08-compline",
                "date": {"year": 2026, "month": 12, "day": 8},
                "hour": "compline",
                "titleLatin": "Ad Completorium",
                "titleEnglish": "Compline",
                "contextLabel": "In Conceptione Immaculata B. Mariae Virginis",
                "sourceVersion": "Rubrics 1960 - 1960",
                "format": "authoritativeOrdered",
                "visibleContentDigest": "fixture",
                "observance": {
                  "observanceID": "in-conceptione-immaculata",
                  "titleLatin": "In Conceptione Immaculata B. Mariae Virginis",
                  "titleEnglish": "The Immaculate Conception of the Blessed Virgin Mary",
                  "rank": "firstClass",
                  "color": "white",
                  "season": "Advent",
                  "eveningContext": null,
                  "commemorations": []
                },
                "sections": [
                  {
                    "id": "compline-rubric-1",
                    "kind": "rubric",
                    "title": "Rubrica",
                    "rubric": null,
                    "latin": "Examen conscientiæ vel Pater Noster totum secreto.",
                    "english": null,
                    "chant": null
                  },
                  {
                    "id": "compline-prayer-1",
                    "kind": "prayer",
                    "title": "Oratio",
                    "rubric": "Orémus.",
                    "latin": "Visita, quǽsumus, Dómine, habitatiónem istam.",
                    "english": "Visit, we beseech thee, O Lord, this dwelling.",
                    "chant": null
                  }
                ]
              }
            ]
            """.utf8
        )

        let offices = try JSONDecoder.hoursContentDecoder.decode(
            [OfficeDocument].self,
            from: data
        )

        XCTAssertEqual(offices.map(\.hour), [.matins, .vespers, .compline])
        XCTAssertTrue(
            offices.allSatisfy { office in
                office.format == .authoritativeOrdered
                    && office.sections.contains(where: { $0.kind == .rubric })
                    && office.sections.contains(where: { $0.kind == .prayer })
            }
        )
        XCTAssertEqual(offices[1].observance?.eveningContext, .secondVespers)
    }

    func testVisibleContentDigestMatchesCompilerCanonicalJSON() throws {
        let sections = [
            OfficeSection(
                id: "rubric",
                kind: .rubric,
                title: "Rubrica",
                latin: "Examen conscientiæ vel Pater Noster totum secreto."
            ),
            OfficeSection(
                id: "prayer",
                kind: .prayer,
                title: "Oratio",
                rubric: "Orémus.",
                latin: "Visita, quǽsumus, Dómine, habitatiónem istam.",
                english: "Visit, we beseech thee, O Lord, this dwelling."
            )
        ]

        XCTAssertEqual(
            try VisibleContentDigest.calculate(for: sections),
            "ff80d1a2af65bd895169d8f7cb2414ef35ee2f55e141cb365fc3e40c5a218487"
        )
    }

    func testSwiftDecodesCompilerCompactTimelineEvents() throws {
        let event = try JSONDecoder.hoursContentDecoder.decode(
            ChantEvent.self,
            from: Data(
                """
                {
                  "i": "note-1",
                  "p": "phrase-1",
                  "y": "syllable-1",
                  "s": "Ma",
                  "n": 0,
                  "d": 1.5,
                  "m": ["mora"],
                  "c": {"k": "c", "l": 2, "b": false}
                }
                """.utf8
            )
        )

        XCTAssertEqual(event.id, "note-1")
        XCTAssertEqual(event.durationWeight, 1.5)
        XCTAssertEqual(event.modifiers, [.mora])
        XCTAssertEqual(event.clef, ChantClef(kind: .c, line: 2))
    }
}
