import XCTest
@testable import HoursCore

final class GregorianLayoutTests: XCTestCase {
    func testGeneratedCatalogContainsCanonicalExsurgeGeometry() {
        XCTAssertEqual(GregorianGlyphName.allCases.count, 49)
        let punctum = GregorianGlyphCatalog.definition(for: .punctumQuadratum)
        XCTAssertEqual(punctum.bounds.width, 100, accuracy: 0.001)
        XCTAssertEqual(punctum.bounds.height, 123.438, accuracy: 0.001)
        XCTAssertEqual(punctum.origin.x, 50, accuracy: 0.001)
        XCTAssertFalse(punctum.paths.flatMap { $0 }.isEmpty)

        for name in GregorianGlyphName.allCases where name != .none {
            XCTAssertFalse(
                GregorianGlyphCatalog.definition(for: name).paths.flatMap { $0 }.isEmpty,
                "\(name.rawValue) should have generated vector commands"
            )
        }
    }

    func testNamedFormsSelectCanonicalCompositeGlyphs() throws {
        let events = [
            ChantEvent(id: "p0", phraseID: "p", syllableID: "s0", syllable: "Po", relativePitch: 0),
            ChantEvent(id: "p1", phraseID: "p", syllableID: "s0", syllable: "Po", relativePitch: 1),
            ChantEvent(id: "r0", phraseID: "p", syllableID: "s1", syllable: "rec", relativePitch: 2),
            ChantEvent(id: "r1", phraseID: "p", syllableID: "s1", syllable: "rec", relativePitch: 1),
            ChantEvent(id: "r2", phraseID: "p", syllableID: "s1", syllable: "rec", relativePitch: 2)
        ]
        let score = try GregorianScoreParser.parse(
            gabc: "name: composite; %% (c4) Po(fg) rec(hgh) (::)",
            timeline: ChantTimeline(events: events)
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        let names = layout.glyphs.map(\.kind.catalogName)

        XCTAssertTrue(names.contains(.podatusLower))
        XCTAssertTrue(names.contains(.podatusUpper))
        XCTAssertTrue(names.contains(.porrectus1))
    }

    func testBundledCorpusPassesNativeNotationValidation() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let days = try await repository.availableDays()
        var offices: [OfficeDocument] = []
        for day in days {
            for hour in OfficeHour.allCases {
                offices.append(try await repository.office(on: day.date, hour: hour))
            }
        }
        XCTAssertNoThrow(try GregorianCorpusValidator.validate(offices: offices))
    }

    func testResponsiveLayoutProducesCustodesAndStableEventFrames() throws {
        let score = try parsedFixture(noteCount: 12)
        let engine = GregorianEngravingLayoutEngine()
        let narrow = engine.layout(score: score, width: 280)
        let wide = engine.layout(score: score, width: 760)

        XCTAssertGreaterThan(narrow.staffs.count, wide.staffs.count)
        XCTAssertLessThanOrEqual(narrow.staffs.count, 3)
        XCTAssertEqual(narrow.events.map(\.eventID), score.eventIDs)
        XCTAssertEqual(Set(narrow.events.map(\.eventID)).count, score.eventIDs.count)
        XCTAssertEqual(
            narrow.glyphs.filter {
                if case .custos = $0.kind { return true }
                return false
            }.count,
            max(0, narrow.staffs.count - 1)
        )
        let countsByLine = Dictionary(grouping: narrow.neumes, by: \.lineIndex)
            .sorted { $0.key < $1.key }
            .map { $0.value.count }
        XCTAssertGreaterThanOrEqual(countsByLine.dropLast().min() ?? 0, 3)
        XCTAssertEqual(
            narrow.glyphs.filter {
                if case .cClef = $0.kind { return true }
                return false
            }.count,
            narrow.staffs.count
        )
    }

    func testMobileStaffsUseFullWidthAndCompactVerticalRhythm() throws {
        let noteCount = 40
        let timeline = ChantTimeline(
            events: (0..<noteCount).map { index in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: "la",
                    relativePitch: 0
                )
            }
        )
        let body = (0..<noteCount)
            .map { _ in "la(f)" }
            .joined(separator: " ")
        let score = try GregorianScoreParser.parse(
            gabc: "name: compact-mobile; %% (c4) \(body) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)

        XCTAssertGreaterThan(layout.staffs.count, 1)
        XCTAssertTrue(layout.initials.isEmpty)
        for staff in layout.staffs {
            XCTAssertEqual(staff.frame.minX, 8, accuracy: 0.01)
            XCTAssertEqual(staff.frame.maxX, 382, accuracy: 0.01)
        }

        for pair in zip(layout.staffs, layout.staffs.dropFirst()) {
            let systemAdvance = pair.1.frame.minY - pair.0.frame.minY
            XCTAssertGreaterThan(systemAdvance, 79)
            XCTAssertLessThan(systemAdvance, 82)
        }
    }

    func testOpeningInitialWithConclusionSitsLeftOfTheFirstClefAndLeavesLaterStaffsFullWidth() throws {
        let syllables = ["Cla", "ma", "vé", "runt", "iu", "sti"]
        let timeline = ChantTimeline(
            events: syllables.enumerated().map { index, syllable in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: syllable,
                    relativePitch: index % 4
                )
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: initial; %% (c4) Cla(f)ma(g)vé(h)runt(i) (z) iu(j)sti(i) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(
            score: score,
            width: 390,
            openingLabel: "8g"
        )
        let initial = try XCTUnwrap(layout.initials.first)
        let firstLyric = try XCTUnwrap(layout.lyrics.first)

        XCTAssertEqual(layout.initials.count, 1)
        XCTAssertEqual(initial.text, "C")
        XCTAssertEqual(initial.neumeID, score.neumes[0].id)
        XCTAssertEqual(firstLyric.text, "la")
        XCTAssertEqual(score.neumes[0].lyric, "Cla")
        XCTAssertGreaterThan(layout.staffs[0].frame.minX, 8)
        XCTAssertLessThanOrEqual(
            initial.origin.x + initial.width,
            layout.staffs[0].frame.minX
        )
        XCTAssertEqual(layout.staffs[1].frame.minX, 8, accuracy: 0.01)
        XCTAssertEqual(layout.staffs[1].frame.maxX, 382, accuracy: 0.01)
    }

    func testOpeningInitialPreservesLatinLigatureAsOneCharacter() throws {
        let timeline = ChantTimeline(
            events: [
                ChantEvent(
                    id: "event-0",
                    phraseID: "phrase-0",
                    syllableID: "syllable-0",
                    syllable: "Æ",
                    relativePitch: 0
                ),
                ChantEvent(
                    id: "event-1",
                    phraseID: "phrase-0",
                    syllableID: "syllable-1",
                    syllable: "tér",
                    relativePitch: 1
                )
            ]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: ligature; %% (c4) 1. Æ(f)tér(g) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(
            score: score,
            width: 390,
            openingLabel: "1f"
        )

        XCTAssertEqual(layout.initials.map(\.text), ["Æ"])
        XCTAssertEqual(layout.initials.map(\.annotation), ["1F"])
        XCTAssertFalse(layout.lyrics.contains { $0.text == "Æ" })
    }

    func testOpeningWithoutConclusionKeepsCompleteLyricUnderClef() throws {
        let timeline = ChantTimeline(
            events: [
                ChantEvent(
                    id: "event-0",
                    phraseID: "phrase-0",
                    syllableID: "syllable-0",
                    syllable: "De",
                    relativePitch: 0
                ),
                ChantEvent(
                    id: "event-1",
                    phraseID: "phrase-0",
                    syllableID: "syllable-1",
                    syllable: "us",
                    relativePitch: 1
                )
            ]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: no-conclusion; %% (c4) De(f)us(g) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(
            score: score,
            width: 390,
            openingLabel: "6"
        )

        XCTAssertTrue(layout.initials.isEmpty)
        XCTAssertEqual(layout.lyrics.first?.text, "De")
        XCTAssertEqual(layout.staffs[0].frame.minX, 8, accuracy: 0.01)
    }

    func testOpeningLabelRequiresModeAndConclusion() {
        XCTAssertNil(GregorianEngravingLayoutEngine.openingLabel(forMode: nil))
        XCTAssertNil(GregorianEngravingLayoutEngine.openingLabel(forMode: "6"))
        XCTAssertNil(GregorianEngravingLayoutEngine.openingLabel(forMode: "6-alt"))
        XCTAssertNil(GregorianEngravingLayoutEngine.openingLabel(forMode: "in-directum"))
        XCTAssertEqual(
            GregorianEngravingLayoutEngine.openingLabel(forMode: "8g"),
            "8G"
        )
        XCTAssertEqual(
            GregorianEngravingLayoutEngine.openingLabel(forMode: "7c2"),
            "7C2"
        )
        XCTAssertEqual(
            GregorianEngravingLayoutEngine.openingLabel(forMode: "4-alt-d"),
            "4-ALT-D"
        )
    }

    func testScoreModeAppearsAboveInitialAndOverridesVerseNumber() throws {
        let timeline = ChantTimeline(
            events: [
                ChantEvent(
                    id: "event-0",
                    phraseID: "phrase-0",
                    syllableID: "syllable-0",
                    syllable: "Prín",
                    relativePitch: 0
                ),
                ChantEvent(
                    id: "event-1",
                    phraseID: "phrase-0",
                    syllableID: "syllable-1",
                    syllable: "cipes",
                    relativePitch: 1
                )
            ]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: psalm-tone; %% (c3) 1. Prín(f)cipes(g) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(
            score: score,
            width: 390,
            openingLabel: "7c2"
        )
        let initial = try XCTUnwrap(layout.initials.first)

        XCTAssertEqual(initial.text, "P")
        XCTAssertEqual(initial.annotation, "7C2")
        XCTAssertNotNil(initial.annotationOrigin)
    }

    func testTerceHymnUsesReferenceLikeMobileDensity() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 24),
            hour: .terce
        )
        let chant = try XCTUnwrap(
            office.sections.compactMap(\.chant).first {
                $0.incipit.hasPrefix("Nunc Sancte nobis Spíritus")
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: chant.gabc,
            timeline: chant.timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        let lyricLines = Dictionary(grouping: layout.neumes, by: \.lineIndex)
            .sorted { $0.key < $1.key }
            .map { $0.value.map(\.lyric).filter { !$0.isEmpty }.joined(separator: " ") }

        XCTAssertEqual(
            layout.staffs.count,
            8,
            "Unexpected mobile wraps: \(lyricLines)"
        )
        XCTAssertLessThanOrEqual(layout.size.height, 650)
        XCTAssertEqual(layout.staffs[0].frame.minX, 8, accuracy: 0.01)
        XCTAssertEqual(layout.staffs[0].frame.maxX, 382, accuracy: 0.01)
        for staff in layout.staffs.dropFirst() {
            XCTAssertEqual(staff.frame.minX, 8, accuracy: 0.01)
            XCTAssertEqual(staff.frame.maxX, 382, accuracy: 0.01)
        }
    }

    func testNeumeTargetsRemainUsableAndDoNotOverlap() throws {
        let score = try parsedFixture(noteCount: 9)
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)

        for neume in layout.neumes {
            XCTAssertGreaterThanOrEqual(neume.hitFrame.width, 23.9)
            XCTAssertGreaterThanOrEqual(neume.hitFrame.height, 43.9)
            XCTAssertFalse(neume.inkFrame.isNull)
        }
        for line in Dictionary(grouping: layout.neumes, by: \.lineIndex).values {
            let ordered = line.sorted { $0.hitFrame.minX < $1.hitFrame.minX }
            for pair in zip(ordered, ordered.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.hitFrame.maxX, pair.1.hitFrame.minX + 0.01)
            }
        }
    }

    func testLyricsAreMeasuredAndDoNotOverlapOnEachLine() throws {
        let score = try parsedFixture(noteCount: 9)
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        for staff in layout.staffs {
            let lyrics = layout.lyrics
                .filter { lyric in
                    lyric.origin.y >= staff.frame.minY && lyric.origin.y < staff.frame.minY + 94
                }
                .sorted { $0.origin.x < $1.origin.x }
            for pair in zip(lyrics, lyrics.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.origin.x + pair.0.width, pair.1.origin.x + 0.5)
            }
        }
    }

    func testAccentedLyricReservesItsBoldAdvanceBeforeFollowingSyllable() throws {
        let syllables = ["con", "fun", "*dán*", "tur"]
        let timeline = ChantTimeline(
            events: syllables.enumerated().map { index, syllable in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: syllable,
                    relativePitch: index
                )
            }
        )
        let accentedScore = try GregorianScoreParser.parse(
            gabc: "name: accented-spacing; %% (c4) con(f)fun(g)*dán*(h)tur(i) (::)",
            timeline: timeline
        )
        let regularScore = try GregorianScoreParser.parse(
            gabc: "name: regular-spacing; %% (c4) con(f)fun(g)dán(h)tur(i) (::)",
            timeline: timeline
        )
        let engine = GregorianEngravingLayoutEngine()
        let accentedLayout = engine.layout(score: accentedScore, width: 760)
        let regularLayout = engine.layout(score: regularScore, width: 760)
        let accentedLyric = try XCTUnwrap(
            accentedLayout.lyrics.first { $0.text == "dán" }
        )
        let regularLyric = try XCTUnwrap(
            regularLayout.lyrics.first { $0.text == "dán" }
        )
        let followingLyric = try XCTUnwrap(
            accentedLayout.lyrics.first { $0.text == "tur" }
        )

        XCTAssertEqual(accentedLyric.style, .accented)
        XCTAssertGreaterThan(accentedLyric.width, regularLyric.width)
        XCTAssertLessThanOrEqual(
            accentedLyric.origin.x + accentedLyric.width,
            followingLyric.origin.x + 0.5
        )
    }

    func testSyllablesStayGroupedWithinWords() throws {
        let syllables = ["San", "cte", "no", "bis", "Spí", "ri", "tus"]
        let timeline = ChantTimeline(
            events: syllables.enumerated().map { index, syllable in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: syllable,
                    relativePitch: index % 4
                )
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: word-spacing; %% (c4) San(f)cte(g) no(h)bis(i) Spí(j)ri(i)tus(h) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 760)
        let lyricsByID = Dictionary(uniqueKeysWithValues: layout.lyrics.map { ($0.neumeID, $0) })
        let neumes = score.neumes

        func gap(after firstIndex: Int, before secondIndex: Int) throws -> CGFloat {
            let first = try XCTUnwrap(lyricsByID[neumes[firstIndex].id])
            let second = try XCTUnwrap(lyricsByID[neumes[secondIndex].id])
            return second.origin.x - (first.origin.x + first.width)
        }

        XCTAssertLessThanOrEqual(try gap(after: 0, before: 1), 2)
        XCTAssertGreaterThanOrEqual(try gap(after: 1, before: 2), 4)
        XCTAssertLessThanOrEqual(try gap(after: 1, before: 2), 7)
        XCTAssertLessThanOrEqual(try gap(after: 2, before: 3), 2)
        XCTAssertGreaterThanOrEqual(try gap(after: 3, before: 4), 4)
        XCTAssertLessThanOrEqual(try gap(after: 3, before: 4), 7)
        XCTAssertLessThanOrEqual(try gap(after: 4, before: 5), 2)
        XCTAssertLessThanOrEqual(try gap(after: 5, before: 6), 2)
    }

    func testLedgerLinesAppearForNotesOutsideTheStaff() throws {
        let timeline = ChantTimeline(
            events: [
                ChantEvent(
                    id: "low",
                    phraseID: "p",
                    syllableID: "s1",
                    syllable: "Low",
                    relativePitch: -7
                ),
                ChantEvent(
                    id: "high",
                    phraseID: "p",
                    syllableID: "s2",
                    syllable: "high",
                    relativePitch: 7
                )
            ]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: ledger; %% (c4) Low(a) high(m) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        XCTAssertTrue(
            layout.strokes.contains {
                if case .ledger = $0.kind { return true }
                return false
            }
        )
    }

    private func parsedFixture(noteCount: Int) throws -> GregorianScore {
        let syllables = (0..<noteCount).map { "s\($0)" }
        let body = syllables.enumerated().map { index, syllable in
            "\(syllable)(\(Character(UnicodeScalar(102 + index % 7)!)))"
        }.joined(separator: " ")
        let events = syllables.enumerated().map { index, syllable in
            ChantEvent(
                id: "event-\(index)",
                phraseID: "phrase-0",
                syllableID: "syllable-\(index)",
                syllable: syllable,
                relativePitch: index % 7
            )
        }
        return try GregorianScoreParser.parse(
            gabc: "name: layout; %% (c4) \(body) (::)",
            timeline: ChantTimeline(events: events)
        )
    }
}
