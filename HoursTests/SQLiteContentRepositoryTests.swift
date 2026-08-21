import XCTest
import SQLite3
@testable import HoursCore

final class SQLiteContentRepositoryTests: XCTestCase {
    func testPrimeMartyrologyDoesNotRepeatStructuredHeadingInBody() async throws {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "base-office",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let repository = try SQLiteContentRepository(
            databaseURL: try XCTUnwrap(url)
        )

        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 9, day: 2),
            hour: .prime
        )
        let martyrology = try XCTUnwrap(office.sections.first {
            $0.title == "Martyrologium" && $0.rubric == "anticipatur"
        })

        XCTAssertEqual(martyrology.titleEnglish, "Martyrology")
        XCTAssertEqual(martyrology.rubricEnglish, "anticipated")
        XCTAssertFalse(
            martyrology.latin.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("Martyrologium {anticipatur}")
        )
        XCTAssertFalse(
            martyrology.english?.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("Martyrology {anticipated}") == true
        )
    }

    func testBundledPerennialReleaseCorpusLoadsOffline() async throws {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "base-office", withExtension: "sqlite", subdirectory: "Resources")
            ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let databaseURL = try XCTUnwrap(url)
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)

        let days = try await repository.availableDays()
        XCTAssertEqual(days.count, 4_383)
        XCTAssertEqual(days.first?.date, LocalDay(year: 2025, month: 1, day: 1))
        XCTAssertEqual(days.last?.date, LocalDay(year: 2036, month: 12, day: 31))

        let pilotDay = LocalDay(year: 2026, month: 7, day: 23)
        let offices = try await OfficeHour.allCases.asyncMap {
            try await repository.office(on: pilotDay, hour: $0)
        }
        XCTAssertEqual(offices.map(\.hour), OfficeHour.allCases)
        XCTAssertTrue(offices.allSatisfy { !$0.playableScores.isEmpty })
        XCTAssertTrue(offices.allSatisfy { $0.format == .authoritativeOrdered })
        XCTAssertTrue(offices.allSatisfy { $0.visibleContentDigest?.isEmpty == false })

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
        XCTAssertTrue(sourceRubrics.allSatisfy { $0.userFacingRubric == nil })
    }

    func testNormalizedCorpusSupportsLazyRangesAdjacencyAndSearch() async throws {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "base-office",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let repository = try SQLiteContentRepository(databaseURL: try XCTUnwrap(url))
        let schemaVersion = await repository.contentSchemaVersion()
        XCTAssertEqual(schemaVersion, 3)

        var rawDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url!.path, &rawDatabase, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(rawDatabase) }
        var rawStatement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                rawDatabase,
                "SELECT COUNT(*) FROM text_fts WHERE text_fts MATCH 'Salve'",
                -1,
                &rawStatement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(rawStatement) }
        XCTAssertEqual(sqlite3_step(rawStatement), SQLITE_ROW)
        XCTAssertGreaterThan(sqlite3_column_int64(rawStatement, 0), 0)

        let coverage = try await repository.coverageRange()
        XCTAssertEqual(
            coverage,
            LocalDay(year: 2025, month: 1, day: 1)...LocalDay(year: 2036, month: 12, day: 31)
        )
        let interval = try await repository.days(
            in: LocalDay(year: 2026, month: 4, day: 5)...LocalDay(year: 2026, month: 4, day: 12)
        )
        XCTAssertEqual(interval.count, 8)
        let adjacent = try await repository.adjacentDay(
            to: LocalDay(year: 2026, month: 4, day: 5),
            direction: .next
        )
        XCTAssertEqual(
            adjacent.date,
            LocalDay(year: 2026, month: 4, day: 6)
        )

        let hits = try await repository.searchHits(
            query: "Salve Regina",
            language: .latin,
            kind: .antiphon,
            limit: 50
        )
        XCTAssertFalse(hits.isEmpty)
        XCTAssertLessThanOrEqual(hits.count, 50)
        XCTAssertTrue(hits.contains(where: \.hasScoredRealizations))
        let normalizedSnippet = hits[0].snippet.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "la")
        )
        XCTAssertTrue(normalizedSnippet.contains("salve"))
        XCTAssertTrue(normalizedSnippet.contains("regina"))
        let usageRange = LocalDay(year: 2026, month: 1, day: 8)
            .liturgicalYearRange
        let details = try await hits.prefix(8).asyncMap {
            try await repository.searchDetail(
                id: $0.id,
                usageRange: usageRange
            )
        }
        XCTAssertTrue(details.contains { !$0.scoredRealizations.isEmpty })
        XCTAssertTrue(details.contains { !$0.contexts.isEmpty })
        for result in details {
            let contextKeys = result.contexts.map {
                "\($0.observanceID ?? "")|\($0.hour.rawValue)|\($0.observanceTitleLatin)"
            }
            XCTAssertEqual(
                Set(contextKeys).count,
                contextKeys.count,
                "Usage contexts must collapse repeated dates for one observance and hour."
            )
            XCTAssertTrue(result.contexts.allSatisfy {
                usageRange.contains($0.firstDate) && usageRange.contains($0.lastDate)
            })
        }

        let firstDetail = try XCTUnwrap(details.first)
        var usageStatement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                rawDatabase,
                """
                SELECT COUNT(*)
                FROM text_recipes
                JOIN office_schedule ON office_schedule.recipe_id = text_recipes.recipe_id
                JOIN text_resources ON text_resources.id = text_recipes.text_id
                WHERE text_resources.stable_key = ?
                  AND office_schedule.date BETWEEN ? AND ?
                """,
                -1,
                &usageStatement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(usageStatement) }
        XCTAssertEqual(
            sqlite3_bind_text(usageStatement, 1, firstDetail.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)),
            SQLITE_OK
        )
        XCTAssertEqual(
            sqlite3_bind_text(usageStatement, 2, usageRange.lowerBound.description, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)),
            SQLITE_OK
        )
        XCTAssertEqual(
            sqlite3_bind_text(usageStatement, 3, usageRange.upperBound.description, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(usageStatement), SQLITE_ROW)
        XCTAssertEqual(
            firstDetail.contexts.reduce(0) { $0 + $1.occurrenceCount },
            Int(sqlite3_column_int64(usageStatement, 0)),
            "Grouped usage counts must account for every scheduled office."
        )

        let teLucisHits = try await repository.searchHits(
            query: "te lucis ante",
            language: .latin,
            kind: .hymn,
            limit: 10
        )
        let teLucisDetails = try await teLucisHits.asyncMap {
            try await repository.searchDetail(
                id: $0.id,
                usageRange: usageRange
            )
        }
        let januaryEighth = LocalDay(year: 2026, month: 1, day: 8)
        let januaryEighthUsage = try XCTUnwrap(
            teLucisDetails.flatMap(\.contexts).first {
                $0.date == januaryEighth && $0.hour == .compline
            }
        )
        XCTAssertEqual(januaryEighthUsage.dayTitleLatin, "Die Octava Januarii")
        XCTAssertFalse(januaryEighthUsage.settingModes.isEmpty)

        let accentInsensitive = try await repository.searchHits(
            query: "domine",
            language: .latin,
            kind: nil,
            limit: 5
        )
        XCTAssertFalse(accentInsensitive.isEmpty)

        for (query, language) in [
            ("a", LiturgicalSearchLanguage.latin),
            ("et", .latin),
            ("domine", .latin),
            ("Lord", .english)
        ] {
            let broad = try await repository.searchHits(
                query: query,
                language: language,
                kind: nil,
                limit: 50
            )
            XCTAssertEqual(broad.count, 50, "Broad query \(query) should fill the result page.")
        }
        let ligatureAlias = try await repository.searchHits(
            query: "misericordiae",
            language: .latin,
            kind: nil,
            limit: 10
        )
        XCTAssertFalse(ligatureAlias.isEmpty)
        let englishOnly = try await repository.searchHits(
            query: "the",
            language: .english,
            kind: nil,
            limit: 50
        )
        XCTAssertEqual(englishOnly.count, 50, "Latin candidates must not starve English results.")
        XCTAssertTrue(englishOnly.allSatisfy { $0.snippetLanguage == .english })
        let complineHymns = try await repository.searchHits(
            query: "a",
            language: .latin,
            kind: .hymn,
            hour: .compline,
            requiresScore: false,
            limit: 20
        )
        XCTAssertFalse(complineHymns.isEmpty)
        XCTAssertTrue(complineHymns.allSatisfy { $0.kind == .hymn })
        for hit in complineHymns.prefix(5) {
            let detail = try await repository.searchDetail(id: hit.id)
            XCTAssertTrue(detail.contexts.contains { $0.hour == .compline })
        }
        let chants = try await repository.searchHits(
            query: "domine",
            language: .latin,
            kind: nil,
            hour: nil,
            requiresScore: true,
            limit: 20
        )
        XCTAssertFalse(chants.isEmpty)
        XCTAssertTrue(chants.allSatisfy(\.hasScoredRealizations))
        let noHits = try await repository.searchHits(
            query: "zzzxxyyqqq",
            language: .all,
            kind: nil,
            limit: 50
        )
        XCTAssertTrue(noHits.isEmpty)

        let cancelledSearch = Task {
            try await repository.searchHits(
                query: "a",
                language: .all,
                kind: nil,
                limit: 50
            )
        }
        cancelledSearch.cancel()
        do {
            _ = try await cancelledSearch.value
            XCTFail("Expected broad search cancellation")
        } catch is CancellationError {
            // Expected.
        }

        do {
            _ = try await repository.day(on: LocalDay(year: 2101, month: 1, day: 1))
            XCTFail("Expected an explicit coverage error")
        } catch ContentRepositoryError.dateOutOfCoverage {
            // Expected.
        }
    }

    func testSearchFiltersByTypeOfficeAndChantAvailability() async throws {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "base-office",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let repository = try SQLiteContentRepository(databaseURL: try XCTUnwrap(url))

        let complineHymns = try await repository.searchHits(
            query: "a",
            language: .latin,
            kind: .hymn,
            hour: .compline,
            requiresScore: false,
            limit: 20
        )
        XCTAssertFalse(complineHymns.isEmpty)
        XCTAssertTrue(complineHymns.allSatisfy { $0.kind == .hymn })
        for hit in complineHymns.prefix(5) {
            let detail = try await repository.searchDetail(id: hit.id)
            XCTAssertTrue(detail.contexts.contains { $0.hour == .compline })
        }

        let chants = try await repository.searchHits(
            query: "domine",
            language: .latin,
            kind: nil,
            hour: nil,
            requiresScore: true,
            limit: 20
        )
        XCTAssertFalse(chants.isEmpty)
        XCTAssertTrue(chants.allSatisfy(\.hasScoredRealizations))
    }

    func testSearchFiltersOfficeTitlesInLatinAndEnglish() async throws {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "base-office",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let repository = try SQLiteContentRepository(databaseURL: try XCTUnwrap(url))
        let firstDay = LocalDay(year: 2026, month: 1, day: 1)
        let lastDay = LocalDay(year: 2026, month: 12, day: 31)
        let calendarYear = firstDay...lastDay

        let latin = try await repository.searchOfficeTitles(
            query: "S. Ludovici",
            language: .latin,
            hour: nil,
            usageRange: calendarYear,
            limit: 50
        )
        let english = try await repository.searchOfficeTitles(
            query: "Saint Louis",
            language: .english,
            hour: nil,
            usageRange: calendarYear,
            limit: 50
        )

        XCTAssertEqual(Set(latin.map(\.hour)), Set(OfficeHour.allCases))
        XCTAssertEqual(Set(english.map(\.hour)), Set(OfficeHour.allCases))
        XCTAssertEqual(Set(latin.map(\.observanceID)), Set(english.map(\.observanceID)))
        XCTAssertTrue(latin.allSatisfy {
            $0.observanceTitleLatin.contains("Ludovici")
                && $0.firstDate == LocalDay(year: 2026, month: 8, day: 25)
                && $0.occurrenceCount == 1
        })
        XCTAssertTrue(english.allSatisfy {
            $0.observanceTitleEnglish?.contains("Saint Louis") == true
        })

        let vespers = try await repository.searchOfficeTitles(
            query: "Saint Louis",
            language: .english,
            hour: .vespers,
            usageRange: calendarYear,
            limit: 50
        )
        XCTAssertEqual(vespers.count, 1)
        XCTAssertEqual(vespers.first?.hour, .vespers)
    }

    func testOfficeTitleSearchCachesHeadersAndEvictsAtItsBound() async throws {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "base-office",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let repository = try SQLiteContentRepository(
            databaseURL: try XCTUnwrap(url)
        )
        let calendarYear = LocalDay(year: 2026, month: 1, day: 1)...LocalDay(
            year: 2026,
            month: 12,
            day: 31
        )

        _ = try await repository.searchOfficeTitles(
            query: "Dominica",
            language: .latin,
            usageRange: calendarYear
        )
        let coldMetrics = await repository.cacheMetricsForTesting()
        XCTAssertGreaterThan(coldMetrics.recipeHeaderEntries, 0)
        XCTAssertEqual(coldMetrics.recipeHeaderHits, 0)

        _ = try await repository.searchOfficeTitles(
            query: "Sancti",
            language: .latin,
            usageRange: calendarYear
        )
        let warmMetrics = await repository.cacheMetricsForTesting()
        XCTAssertEqual(
            warmMetrics.recipeHeaderEntries,
            coldMetrics.recipeHeaderEntries
        )
        XCTAssertEqual(
            warmMetrics.recipeHeaderHits,
            coldMetrics.recipeHeaderEntries
        )

        _ = try await repository.searchOfficeTitles(
            query: "zzzxxyyqqq",
            language: .all,
            usageRange: nil
        )
        let boundedMetrics = await repository.cacheMetricsForTesting()
        XCTAssertEqual(boundedMetrics.recipeHeaderEntries, 4_096)

        let cancelledSearch = Task {
            try await repository.searchOfficeTitles(
                query: "Dominica",
                language: .latin,
                usageRange: nil
            )
        }
        cancelledSearch.cancel()
        do {
            _ = try await cancelledSearch.value
            XCTFail("Expected office-title search cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testSearchCollapsesDuplicateRepresentationsOfTheSamePassage() async throws {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: "base-office",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? bundle.url(forResource: "base-office", withExtension: "sqlite")
        let repository = try SQLiteContentRepository(databaseURL: try XCTUnwrap(url))

        let hits = try await repository.searchHits(
            query: "ensigns",
            language: .all,
            kind: nil,
            limit: 50
        )

        let psalm735Hits = hits.filter { $0.snippet.hasPrefix("73:5 ") }
        XCTAssertEqual(psalm735Hits.count, 1)
        XCTAssertEqual(psalm735Hits.first?.kind, .psalm)
        XCTAssertTrue(psalm735Hits.first?.hasScoredRealizations == true)
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
