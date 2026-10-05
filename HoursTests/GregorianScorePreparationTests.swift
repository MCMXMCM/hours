import HoursCore
@testable import Hours
import XCTest

@MainActor
final class GregorianScorePreparationTests: XCTestCase {
    func testRestoredComplineHymnLyricsRemainInsideTheCanvas() async throws {
        let repository = try SQLiteContentRepository(databaseURL: OfficeTradition.roman1954.databaseURL())
        for (year, month, day) in [(2026, 9, 15), (2025, 8, 19), (2025, 5, 13), (2025, 6, 3), (2025, 12, 2)] {
            let office = try await repository.office(on: LocalDay(year: year, month: month, day: day), hour: .compline)
            let hymn = try XCTUnwrap(office.sections.first { $0.latin.hasPrefix("Te lucis") }?.chant)
            let notation = try GregorianScoreParser.parse(gabc: hymn.gabc, timeline: hymn.timeline)
            for width in [320.0, 402.0, 768.0] {
                let layout = GregorianEngravingLayoutEngine().layout(score: notation, width: width)
                for lyric in layout.lyrics {
                    XCTAssertGreaterThanOrEqual(lyric.origin.x, 0, "\(year)-\(month)-\(day) \(width): \(lyric.text)")
                    XCTAssertLessThanOrEqual(lyric.origin.x + lyric.width, width + 1, "\(year)-\(month)-\(day) \(width): \(lyric.text)")
                }
            }
        }
    }

    func testReaderPresentationPreparesSectionsScoresAndOutlineOnce() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 12, day: 8),
            hour: .vespers
        )
        let expectedSections = OfficeReaderSectionBuilder.displaySections(
            from: office.sections,
            format: office.format
        )

        let presentation = try OfficeReaderPresentation.prepare(
            office: office
        )

        XCTAssertEqual(presentation.officeID, office.id)
        XCTAssertEqual(presentation.sections, expectedSections)
        XCTAssertEqual(
            Set(presentation.scores.map(\.id)).count,
            presentation.scores.count
        )
        XCTAssertEqual(
            presentation.outlineEntries,
            OfficeReaderOutlineBuilder.entries(from: expectedSections)
        )
    }

    func testReaderPresentationHonorsCancellation() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )
        let office = try await repository.office(
            on: LocalDay(year: 2025, month: 12, day: 25),
            hour: .matins
        )
        let preparation = Task.detached {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try OfficeReaderPresentation.prepare(office: office)
        }

        do {
            _ = try await preparation.value
            XCTFail("Expected reader presentation cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testPreparedScoreCacheReusesKeysAndEvictsAtItsBound() async throws {
        let repository = try SQLiteContentRepository(
            databaseURL: bundledDatabaseURL()
        )
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 26),
            hour: .compline
        )
        let score = try XCTUnwrap(
            office.playableScores.min {
                $0.timeline.events.count < $1.timeline.events.count
            }
        )
        // The host app can prepare its reader concurrently with this test.
        let cache = GregorianLayoutCache()
        let metrics = GregorianLayoutMetrics()

        _ = try await cache.preparedScore(
            score: score,
            width: 390,
            metrics: metrics
        )
        _ = try await cache.preparedScore(
            score: score,
            width: 390,
            metrics: metrics
        )
        _ = try await cache.preparedScore(
            score: score,
            width: 391,
            metrics: metrics
        )
        var cacheMetrics = await cache.metricsForTesting()
        XCTAssertEqual(cacheMetrics.preparedScores, 2)
        XCTAssertEqual(cacheMetrics.preparedScoreHits, 1)

        for width in 300..<333 {
            _ = try await cache.preparedScore(
                score: score,
                width: CGFloat(width),
                metrics: metrics
            )
        }
        cacheMetrics = await cache.metricsForTesting()
        XCTAssertEqual(cacheMetrics.preparedScores, 32)
        XCTAssertEqual(cacheMetrics.parsedScores, 1)
    }

    func testBundledComplinePreparesEveryScoreBeforeReaderPresentation() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 26),
            hour: .compline
        )
        var seenScoreIDs: Set<String> = []
        let scores = office.playableScores.filter {
            seenScoreIDs.insert($0.id).inserted
        }
        let preparations = await GregorianScorePreparer.prepare(
            scores: scores,
            width: 390,
            metrics: GregorianLayoutMetrics(
                notationScale: 1,
                lyricScale: 1
            )
        )

        XCTAssertFalse(scores.isEmpty)
        XCTAssertEqual(preparations.count, scores.count)
        for score in scores {
            let preparation = try XCTUnwrap(
                preparations[score.id],
                "Missing prepared layout for \(score.incipit)"
            )
            guard case .ready(let preparedScore) = preparation else {
                return XCTFail(
                    "Failed to prepare layout for \(score.incipit)"
                )
            }

            let layout = preparedScore.layout
            XCTAssertEqual(preparation.height, layout.size.height)
            XCTAssertGreaterThan(layout.size.height, 0)
            if layout.strokes.count > 1 {
                XCTAssertLessThan(
                    preparedScore.drawing.tiles
                        .flatMap(\.strokeBatches)
                        .count,
                    layout.strokes.count
                )
            }
            if layout.glyphs.count > 1 {
                XCTAssertLessThan(
                    preparedScore.drawing.tiles
                        .flatMap(\.glyphPaths)
                        .count,
                    layout.glyphs.count
                )
            }
        }
    }

    private func bundledDatabaseURL() throws -> URL {
        try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite"
            )
        )
    }

    func testPreparedDrawingBatchesStaticScoreOperationsWithoutMergingOverlaps() throws {
        let glyphs = [
            GregorianPlacedGlyph(
                kind: .notehead(.punctum),
                frame: CGRect(x: 10, y: 10, width: 8, height: 8)
            ),
            GregorianPlacedGlyph(
                kind: .notehead(.punctum),
                frame: CGRect(x: 30, y: 10, width: 8, height: 8)
            ),
            GregorianPlacedGlyph(
                kind: .notehead(.punctum),
                frame: CGRect(x: 31, y: 11, width: 8, height: 8)
            )
        ]
        let strokes = [
            GregorianPlacedStroke(
                kind: .staff,
                start: CGPoint(x: 0, y: 8),
                end: CGPoint(x: 100, y: 8),
                lineWidth: 1
            ),
            GregorianPlacedStroke(
                kind: .staff,
                start: CGPoint(x: 0, y: 12),
                end: CGPoint(x: 100, y: 12),
                lineWidth: 1
            ),
            GregorianPlacedStroke(
                kind: .connector,
                start: CGPoint(x: 30, y: 10),
                end: CGPoint(x: 30, y: 20),
                lineWidth: 2
            )
        ]
        let layout = GregorianLayout(
            size: CGSize(width: 100, height: 40),
            staffs: [],
            glyphs: glyphs,
            strokes: strokes,
            lyrics: [],
            events: [],
            neumes: []
        )

        let drawing = GregorianScoreDrawing(layout: layout)
        let tile = try XCTUnwrap(drawing.tiles.first)

        XCTAssertEqual(drawing.tiles.count, 1)
        XCTAssertEqual(tile.strokeBatches.count, 2)
        XCTAssertEqual(tile.glyphPaths.count, 2)
    }

    func testPreparedDrawingUsesExactStaffSystemFramesAsRenderTiles() {
        let firstFrame = CGRect(x: 0, y: 0, width: 100, height: 40)
        let secondFrame = CGRect(x: 0, y: 40, width: 100, height: 50)
        let layout = GregorianLayout(
            size: CGSize(width: 100, height: 90),
            staffs: [
                GregorianStaffLayout(
                    index: 0,
                    frame: CGRect(x: 10, y: 10, width: 80, height: 12),
                    systemFrame: firstFrame,
                    firstEventID: "first"
                ),
                GregorianStaffLayout(
                    index: 1,
                    frame: CGRect(x: 10, y: 50, width: 80, height: 12),
                    systemFrame: secondFrame,
                    firstEventID: "second"
                )
            ],
            glyphs: [
                GregorianPlacedGlyph(
                    kind: .notehead(.punctum),
                    frame: CGRect(x: 20, y: 12, width: 8, height: 8)
                ),
                GregorianPlacedGlyph(
                    kind: .notehead(.punctum),
                    frame: CGRect(x: 20, y: 52, width: 8, height: 8)
                )
            ],
            strokes: [],
            lyrics: [
                GregorianPlacedLyric(
                    text: "First",
                    origin: CGPoint(x: 20, y: 25),
                    width: 30,
                    fontSize: 12,
                    neumeID: "first"
                ),
                GregorianPlacedLyric(
                    text: "Second",
                    origin: CGPoint(x: 20, y: 70),
                    width: 40,
                    fontSize: 12,
                    neumeID: "second"
                )
            ],
            events: [],
            neumes: []
        )

        let drawing = GregorianScoreDrawing(layout: layout)

        XCTAssertEqual(drawing.tiles.map(\.frame), [firstFrame, secondFrame])
        XCTAssertEqual(drawing.tiles.map(\.lyrics.count), [1, 1])
        XCTAssertEqual(drawing.tiles.map(\.glyphPaths.count), [1, 1])
    }

    func testScoreInteractionResolvesATapWithoutPerNeumeViews() {
        let target = GregorianNeumePlacement(
            id: "event-1",
            eventIDs: ["event-1"],
            lyric: "In",
            inkFrame: CGRect(x: 24, y: 20, width: 12, height: 18),
            hitFrame: CGRect(x: 16, y: 8, width: 44, height: 44),
            lineIndex: 0
        )
        let layout = GregorianLayout(
            size: CGSize(width: 390, height: 100),
            staffs: [],
            glyphs: [],
            strokes: [],
            lyrics: [],
            events: [],
            neumes: [target]
        )

        XCTAssertEqual(
            GregorianScoreInteraction.neume(
                at: CGPoint(x: 30, y: 30),
                in: layout
            )?.id,
            target.id
        )
        XCTAssertNil(
            GregorianScoreInteraction.neume(
                at: CGPoint(x: 300, y: 80),
                in: layout
            )
        )
    }

    func testCantorHighlightIncludesWholeNeumeAndCorrespondingSyllable() throws {
        let firstSyllableNeume = GregorianNeumePlacement(
            id: "event-1",
            eventIDs: ["event-1"],
            lyric: "Ky",
            inkFrame: CGRect(x: 10, y: 10, width: 10, height: 10),
            hitFrame: CGRect(x: 5, y: 5, width: 20, height: 20),
            lineIndex: 0
        )
        let activeNeume = GregorianNeumePlacement(
            id: "event-2",
            eventIDs: ["event-2", "event-3"],
            lyric: "",
            inkFrame: CGRect(x: 30, y: 10, width: 16, height: 10),
            hitFrame: CGRect(x: 25, y: 5, width: 26, height: 20),
            lineIndex: 0
        )
        let nextSyllableNeume = GregorianNeumePlacement(
            id: "event-4",
            eventIDs: ["event-4"],
            lyric: "ri",
            inkFrame: CGRect(x: 60, y: 10, width: 10, height: 10),
            hitFrame: CGRect(x: 55, y: 5, width: 20, height: 20),
            lineIndex: 0
        )
        let layout = GregorianLayout(
            size: CGSize(width: 100, height: 40),
            staffs: [],
            glyphs: [],
            strokes: [],
            lyrics: [],
            events: [],
            neumes: [
                firstSyllableNeume,
                activeNeume,
                nextSyllableNeume
            ]
        )
        let events = [
            ChantEvent(
                id: "event-1",
                phraseID: "phrase",
                syllableID: "kyrie-ky",
                syllable: "Ky",
                relativePitch: 0
            ),
            ChantEvent(
                id: "event-2",
                phraseID: "phrase",
                syllableID: "kyrie-ky",
                syllable: "Ky",
                relativePitch: 1
            ),
            ChantEvent(
                id: "event-3",
                phraseID: "phrase",
                syllableID: "kyrie-ky",
                syllable: "Ky",
                relativePitch: 2
            ),
            ChantEvent(
                id: "event-4",
                phraseID: "phrase",
                syllableID: "kyrie-ri",
                syllable: "ri",
                relativePitch: 1
            )
        ]

        let highlight = try XCTUnwrap(
            GregorianCantorHighlight(
                eventID: "event-2",
                timeline: ChantTimeline(events: events),
                layout: layout
            )
        )

        XCTAssertEqual(highlight.neume.id, activeNeume.id)
        XCTAssertEqual(highlight.eventIDs, ["event-2", "event-3"])
        XCTAssertEqual(
            highlight.syllableNeumeIDs,
            ["event-1", "event-2"]
        )
    }
}
