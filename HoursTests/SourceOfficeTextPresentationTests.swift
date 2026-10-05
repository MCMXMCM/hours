@testable import HoursCore
import SQLite3
@testable import Hours
import XCTest

@MainActor
final class SourceOfficeTextPresentationTests: XCTestCase {
    func testEveryAuditedSourceMarkerAndEditorialBracket() throws {
        struct Fixture: Decodable { let source: String; let category: String }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "roman1954-display-text", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.count, 2117)
        for fixture in fixtures {
            let displayed = SourceOfficeTextPresentation.text(fixture.source)
            switch fixture.category {
            case "retainedEditorialBrackets":
                XCTAssertEqual(displayed, fixture.source, fixture.source)
            case "psalmOrdinal":
                let expected = fixture.source.replacingOccurrences(of: #" \[\d+\]$"#, with: "", options: .regularExpression)
                XCTAssertEqual(displayed, expected, fixture.source)
            case "malformedParenthesis":
                XCTAssertEqual(displayed, fixture.source.replacingOccurrences(of: "{", with: "("), fixture.source)
            case "sourceAnnotation":
                XCTAssertFalse(displayed.contains("{"), fixture.source)
                XCTAssertFalse(displayed.contains("}"), fixture.source)
                XCTAssertFalse(displayed.contains("Doxology:"), fixture.source)
                XCTAssertFalse(displayed.contains("Laudes:"), fixture.source)
            default: XCTFail("Unclassified source artifact: \(fixture.category)")
            }
        }
    }

    func testSourceRubricsAndPsalmDivisionsRenderWithoutChangingStoredText() {
        let rubric = OfficeSection(id: "source", kind: .prayer, title: "Psalmi",
            latin: "{ex Psalterio secundum diem}", english: "{from the Psalter for the day of the week}")
        let psalm = OfficeSection(id: "psalm", kind: .psalm, title: "",
            latin: "Psalmus 118(129-144) [1]\n118:129 Mirabília testimónia tua.", english: "Psalm 118(129-144) [1]")
        let displayed = OfficeReaderSectionBuilder.displaySections(from: [rubric, psalm], format: .sourceOrdered)
        XCTAssertEqual(displayed[0].kind, .rubric)
        XCTAssertEqual(displayed[0].rubric, "(ex Psalterio secundum diem)")
        XCTAssertEqual(displayed[0].rubricEnglish, "(from the Psalter for the day of the week)")
        XCTAssertEqual(displayed[1].latin, "Psalmus 118(129-144)\n118:129 Mirabília testimónia tua.")
        XCTAssertEqual(rubric.latin, "{ex Psalterio secundum diem}")
        XCTAssertEqual(SourceOfficeTextPresentation.text("{unresolved-source-command}"), "{unresolved-source-command}")
        XCTAssertEqual(SourceOfficeTextPresentation.text("[in the year 258,]"), "[in the year 258,]")
    }

    func testUnscoredSourcePsalmodyPairsEachVerseWithItsTranslation() {
        let psalm = OfficeSection(id: "psalm", kind: .reading, title: "Psalmi",
            latin: "Psalmus 18(8-15b) [3]\n18:8 Lex Dómini immaculáta, convértens ánimas.\n18:9 Justítiæ Dómini rectæ, lætificántes corda.",
            english: "Psalm 18(8-15b) [3]\n18:8 The law of the Lord is unspotted, converting souls.\n18:9 The justices of the Lord are right, rejoicing hearts.")
        let displayed = SourceOfficeTextPresentation.sections([psalm])
        XCTAssertEqual(displayed[0].kind, .psalm)
        XCTAssertEqual(displayed[0].title, "Psalmus 18(8-15b)")
        XCTAssertEqual(displayed[0].titleEnglish, "Psalm 18(8-15b)")
        XCTAssertEqual(displayed[0].latin,
            "18:8 Lex Dómini immaculáta, convértens ánimas.\n\n18:9 Justítiæ Dómini rectæ, lætificántes corda.")
        XCTAssertEqual(displayed[0].english,
            "18:8 The law of the Lord is unspotted, converting souls.\n\n18:9 The justices of the Lord are right, rejoicing hearts.")
        let lines = PsalmTextFormatter.lines(
            latin: displayed[0].latin,
            english: displayed[0].english,
            startsAfterScoredVerse: false
        )
        // Scripture references are not verse ordinals; each verse is numbered
        // in order within the psalm, as in every other psalm.
        XCTAssertEqual(lines.map(\.number), [1, 2])
        XCTAssertEqual(lines.first?.latin, "Lex Dómini immaculáta, convértens ánimas.")
        XCTAssertEqual(lines.last?.english, "The justices of the Lord are right, rejoicing hearts.")

        // Unequal lines keep the source layout rather than risk a wrong pairing.
        let unequal = OfficeSection(id: "unequal", kind: .psalm, title: "",
            latin: "1:1 Beátus vir.\n1:2 Sed in lege Dómini.",
            english: "1:1 Blessed is the man.")
        XCTAssertEqual(SourceOfficeTextPresentation.sections([unequal])[0].latin, unequal.latin)
    }

    func testUnbracedSourceDirectionsUseRubricTypographyAndTranslateTheSoloDirection() {
        let omission = OfficeSection(id: "omit", kind: .rubric, title: "", latin: "Gloria omittitur", english: "omit Glory be")
        let solo = OfficeSection(id: "solo", kind: .rubric, title: "Lectio 1", latin: "Extra Chorum, quando ab uno tantum recitatur Officium dicitur: Jube, Dómine, benedícere; et subjungitur congruens Benedictio.")
        let displayed = SourceOfficeTextPresentation.sections([omission, solo])
        XCTAssertEqual(displayed[0].rubric, "Gloria omittitur")
        XCTAssertEqual(displayed[0].rubricEnglish, "omit Glory be")
        XCTAssertEqual(displayed[0].latin, "")
        XCTAssertEqual(displayed[1].rubric, solo.latin)
        XCTAssertTrue(displayed[1].rubricEnglish?.contains("one person alone") == true)
        XCTAssertNil(solo.english)
    }

    func testHiddenDoxologyDoesNotLeaveAnEmptyHymnBlock() {
        let label = OfficeSection(id: "label", kind: .hymn, title: "Hymnus", titleEnglish: "Hymn",
            latin: "{Doxology: Special}", english: "{Doxology: Special}")
        let hymn = OfficeSection(id: "hymn", kind: .hymn, title: "",
            latin: "Te lucis ante términum", english: "Before the ending of the day")
        let displayed = SourceOfficeTextPresentation.sections([label, hymn])
        XCTAssertEqual(displayed.count, 1)
        XCTAssertEqual(displayed[0].id, hymn.id)
        XCTAssertEqual(displayed[0].title, "Hymnus")
        XCTAssertEqual(displayed[0].titleEnglish, "Hymn")
        XCTAssertEqual(displayed[0].latin, hymn.latin)
        XCTAssertEqual(displayed[0].english, hymn.english)
    }

    func testPsalmHeadingPromotionNeverHidesPrayerInAnUnpairedTranslation() {
        let psalm = OfficeSection(id: "psalm", kind: .psalm, title: "Psalmi",
            latin: "Psalmus 4 [1]", english: "Psalm 4 [1]\nWhen I called upon him, the God of my justice heard me.")
        let displayed = SourceOfficeTextPresentation.sections([psalm])
        XCTAssertEqual(displayed[0].title, "")
        XCTAssertEqual(displayed[0].latin, "Psalmus 4")
        XCTAssertTrue(displayed[0].english?.contains("the God of my justice heard me") == true)
    }

    func testSourcePartHeadingsAppearOnceWithoutRemovingTheirPrayers() {
        let source = [
            OfficeSection(id: "lesson", kind: .reading, title: "Lectio brevis", latin: "Fratres: Sóbrii estóte."),
            OfficeSection(id: "response", kind: .responsory, title: "Lectio brevis", latin: "℟. Deo grátias."),
            OfficeSection(id: "verse", kind: .versicle, title: "Lectio brevis", latin: "℣. Adjutórium nostrum."),
            OfficeSection(id: "hymn", kind: .hymn, title: "Hymnus", latin: "Te lucis ante términum")
        ]
        let displayed = OfficeReaderSectionBuilder.displaySections(from: source, format: .sourceOrdered)
        XCTAssertEqual(displayed.map(\.title), ["Lectio brevis", "", "", "Hymnus"])
        XCTAssertEqual(displayed.map(\.latin), source.map(\.latin))
        XCTAssertEqual(OfficeReaderOutlineBuilder.entries(from: displayed).map(\.title), ["Lectio brevis", "Hymnus"])
    }

    func testAuthenticComplineKeepsEveryChantAndPrayerInTextAndCompactViews() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let office = try await repository.office(on: LocalDay(year: 2026, month: 9, day: 10), hour: .compline)
        XCTAssertNoThrow(try VisibleContentDigest.validate(office))
        let display = OfficeReaderSectionBuilder.displaySections(from: office.sections, format: office.format)
        XCTAssertEqual(display.compactMap(\.chant), office.sections.compactMap(\.chant))
        XCTAssertTrue(display.contains { $0.rubric == "(ex Psalterio secundum diem)" })
        XCTAssertFalse(display.contains { $0.latin.contains("Psalmus 69 [1]") })
        XCTAssertTrue(display.contains { $0.title == "Psalmus 69" && $0.chant != nil })
        XCTAssertFalse(display.contains { $0.title == "Psalmi" || $0.latin == "Psalmus 69" })
        let compact = OfficeReaderSectionBuilder.displaySections(from: office.sections, format: office.format, usesCompactPsalmody: true)
        XCTAssertFalse(compact.contains { $0.latin.contains("{") || $0.latin.contains("Psalmus 69 [1]") })
        XCTAssertGreaterThan(compact.filter { $0.id.hasSuffix("-compact-continuation") }.count, 2)
        XCTAssertNotEqual(compact, display)
    }
    func testEntireRoman1954CorpusPreservesPrayerThroughNormalAndCompactPresentation() async throws {
        // Traverse each stored text/score pairing once. The SQL relationships
        // cover every scheduled office without decoding repeated timelines
        // tens of thousands of times merely to discard identical sections.
        let url = try OfficeTradition.roman1954.databaseURL()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let connection = try XCTUnwrap(database)
        defer { sqlite3_close(connection) }
        try SharedContentDatabase.prepare(connection, at: url)
        let decoder = JSONDecoder.hoursContentDecoder
        var distinct = 0
        var compacted = 0
        func letters(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "la"))
                .replacingOccurrences(of: "æ", with: "ae")
                .replacingOccurrences(of: "œ", with: "oe")
                .replacingOccurrences(of: "j", with: "i")
                .replacingOccurrences(of: #"[^\p{L}]"#, with: "", options: .regularExpression)
        }
        let sql = """
        WITH used AS (
            SELECT DISTINCT rs.text_id, rs.score_id FROM recipe_sections rs
            JOIN office_schedule os ON os.recipe_id = rs.recipe_id
        )
        SELECT used.text_id, used.score_id, t.payload, s.payload,
               (SELECT count(*) FROM office_schedule)
        FROM used JOIN text_resources t ON t.id = used.text_id
        LEFT JOIN scores s ON s.id = used.score_id
        ORDER BY used.text_id, used.score_id
        """
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(connection, sql, -1, &statement, nil), SQLITE_OK)
        let query = try XCTUnwrap(statement)
        defer { sqlite3_finalize(query) }
        var step = sqlite3_step(query)
        while step == SQLITE_ROW {
            XCTAssertEqual(sqlite3_column_int(query, 4), 35_064)
            func payload(_ column: Int32) throws -> Data {
                let bytes = try XCTUnwrap(sqlite3_column_blob(query, column))
                return try ContentPayloadCodec.decode(Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, column))))
            }
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: payload(2)) as? [String: Any])
            fields["id"] = "text-\(sqlite3_column_int64(query, 0))-score-\(sqlite3_column_int64(query, 1))"
            if sqlite3_column_type(query, 3) != SQLITE_NULL {
                fields["chant"] = try JSONSerialization.jsonObject(with: payload(3))
            }
            let source = try decoder.decode(OfficeSection.self, from: JSONSerialization.data(withJSONObject: fields))
            distinct += 1
            let normal = OfficeReaderSectionBuilder.displaySections(from: [source], format: .sourceOrdered)
            let compact = OfficeReaderSectionBuilder.displaySections(from: [source], format: .sourceOrdered, usesCompactPsalmody: true)
            let context = "\(source.id) \(source.chant?.incipit ?? source.title)"
            XCTAssertFalse(normal.isEmpty, context)
            let expectedLatin = [source.rubric, source.latin].compactMap { $0 }.map(SourceOfficeTextPresentation.text).joined(separator: " ")
            // A psalm's name may become its heading: either the whole text is
            // the name, or the name is the first line above the verses.
            let sourceLatin = SourceOfficeTextPresentation.text(source.latin)
            let promotedHeading = normal.first.map {
                !$0.title.isEmpty
                    && (sourceLatin == $0.title || sourceLatin.hasPrefix($0.title + "\n"))
            } == true
                && (sourceLatin.hasPrefix("Psalmus ") || sourceLatin.hasPrefix("Canticum "))
            let visibleLatin = normal.map { (promotedHeading ? $0.title + " " : "") + ($0.rubric ?? "") + " " + $0.latin }.joined(separator: " ")
            XCTAssertEqual(letters(visibleLatin), letters(expectedLatin), context)
            if source.english != nil {
                let expectedEnglish = [source.rubricEnglish, source.english].compactMap { $0 }.map(SourceOfficeTextPresentation.text).joined(separator: " ")
                let visibleEnglish = normal.map { (promotedHeading ? ($0.titleEnglish ?? "") + " " : "") + ($0.rubricEnglish ?? "") + " " + ($0.english ?? "") }.joined(separator: " ")
                XCTAssertEqual(letters(visibleEnglish), letters(expectedEnglish), context)
            }

            for section in normal {
                for value in [section.latin, section.english ?? "", section.title, section.rubric ?? "", section.rubricEnglish ?? ""] {
                    XCTAssertFalse(value.contains("{") || value.contains("}"), context)
                }
            }
            if compact != normal {
                compacted += 1
                let latin = { (sections: [OfficeSection]) in letters(sections.map(\.latin).joined(separator: " ")) }
                let english = { (sections: [OfficeSection]) in letters(sections.compactMap(\.english).joined(separator: " ")) }
                // Ignore printed verse labels, accents, punctuation and
                // pointing. Every prayer letter must survive in order.
                guard latin(normal) == latin(compact), english(normal) == english(compact) else {
                    return XCTFail("Compact presentation changed prayer content: " + context + "\nLatin equal: \(latin(normal) == latin(compact)); English equal: \(english(normal) == english(compact))")
                }
            }
            step = sqlite3_step(query)
        }
        XCTAssertEqual(step, SQLITE_DONE, String(cString: sqlite3_errmsg(connection)))
        XCTAssertGreaterThan(distinct, 20_000)
        XCTAssertGreaterThan(compacted, 100)
        print("Roman 1954 presentation: all 35064 scheduled offices, \(distinct) distinct sections, \(compacted) compact conversions")
    }

    func testFinalCorpusRestoresVigilMetadataAndKeepsNocteSurgentesAsAHymn() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        let vigil = try await repository.office(on: LocalDay(year: 2026, month: 6, day: 27), hour: .lauds)
        XCTAssertTrue(vigil.observance?.commemorations.contains { $0.titleLatin == "In Vigilia Ss. Petri et Pauli Apostolorum" } == true)
        let matins = try await repository.office(on: LocalDay(year: 2025, month: 8, day: 3), hour: .matins)
        let hymn = try XCTUnwrap(matins.sections.first { $0.latin.contains("Nocte surgéntes vigilémus omnes") })
        XCTAssertEqual(hymn.kind, .hymn)
        let normal = OfficeReaderSectionBuilder.displaySections(from: [hymn], format: .sourceOrdered)
        let compact = OfficeReaderSectionBuilder.displaySections(from: [hymn], format: .sourceOrdered, usesCompactPsalmody: true)
        XCTAssertEqual(normal, compact)
        XCTAssertTrue(normal[0].latin.contains("Semper in psalmis meditémur"))
        XCTAssertNoThrow(try VisibleContentDigest.validate(vigil))
        XCTAssertNoThrow(try VisibleContentDigest.validate(matins))
    }

}
