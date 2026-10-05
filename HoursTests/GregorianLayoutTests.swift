import XCTest
@testable import HoursCore

final class GregorianLayoutTests: XCTestCase {
    func testNotationAndLyricsScaleTogetherAcrossReaderRange() throws {
        let score = try parsedFixture(noteCount: 1)
        let engine = GregorianEngravingLayoutEngine()
        let previousMinimum = engine.layout(
            score: score,
            width: 390,
            metrics: GregorianLayoutMetrics(notationScale: 0.8)
        )
        let newMinimum = engine.layout(
            score: score,
            width: 390,
            metrics: GregorianLayoutMetrics(
                notationScale: GregorianLayoutMetrics.minimumNotationScale
            )
        )
        let clampedBelowMinimum = engine.layout(
            score: score,
            width: 390,
            metrics: GregorianLayoutMetrics(notationScale: 0)
        )
        let defaultSize = engine.layout(
            score: score,
            width: 390
        )
        let maximumSize = engine.layout(
            score: score,
            width: 390,
            metrics: GregorianLayoutMetrics(
                notationScale: GregorianLayoutMetrics.maximumNotationScale
            )
        )
        let previousClef = try XCTUnwrap(previousMinimum.glyphs.first)
        let minimumClef = try XCTUnwrap(newMinimum.glyphs.first)
        let clampedClef = try XCTUnwrap(clampedBelowMinimum.glyphs.first)
        let previousLyric = try XCTUnwrap(previousMinimum.lyrics.first)
        let minimumLyric = try XCTUnwrap(newMinimum.lyrics.first)
        let clampedLyric = try XCTUnwrap(clampedBelowMinimum.lyrics.first)
        let defaultClef = try XCTUnwrap(defaultSize.glyphs.first)
        let maximumClef = try XCTUnwrap(maximumSize.glyphs.first)
        let defaultLyric = try XCTUnwrap(defaultSize.lyrics.first)
        let maximumLyric = try XCTUnwrap(maximumSize.lyrics.first)

        XCTAssertEqual(
            minimumClef.frame.width,
            previousClef.frame.width * 0.75,
            accuracy: 0.001
        )
        XCTAssertEqual(
            clampedClef.frame.width,
            minimumClef.frame.width,
            accuracy: 0.001
        )
        XCTAssertEqual(
            minimumLyric.fontSize,
            previousLyric.fontSize * 0.75,
            accuracy: 0.001
        )
        XCTAssertEqual(
            clampedLyric.fontSize,
            minimumLyric.fontSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            maximumClef.frame.width,
            defaultClef.frame.width
                * GregorianLayoutMetrics.maximumNotationScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            maximumLyric.fontSize,
            defaultLyric.fontSize
                * GregorianLayoutMetrics.maximumNotationScale,
            accuracy: 0.001
        )
    }

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
        // The release corpus spans 35,064 offices. Stream the stored scores
        // instead of retaining every reconstructed office just to deduplicate
        // its notation. Database integrity and office assembly have separate tests.
        let count = try await repository.forEachScoredRealization { score in
            _ = try GregorianScoreParser.parse(
                gabc: score.gabc,
                timeline: score.timeline
            )
        }
        XCTAssertGreaterThan(count, 0)
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
            9,
            "Unexpected mobile wraps: \(lyricLines)"
        )
        XCTAssertLessThanOrEqual(
            layout.size.height,
            810,
            "Selective connectors should preserve the reference-like mobile density."
        )
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

    func testAutomaticHyphensClarifyWideSyllableGapsWithinAWord() throws {
        let syllables = ["De", "us", "in"]
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
        let score = try GregorianScoreParser.parse(
            gabc: "name: hyphens; %% (c3) De(h)us(h) in(h) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 760)
        let lyricTexts = layout.lyrics.map(\.text)

        XCTAssertTrue(lyricTexts.contains("-"))
        XCTAssertTrue(
            layout.lyrics.contains {
                $0.neumeID == "lyric-hyphen-event-0-event-1"
            }
        )
        let firstSyllable = try XCTUnwrap(
            layout.lyrics.first { $0.neumeID == "event-0" }
        )
        let hyphen = try XCTUnwrap(
            layout.lyrics.first {
                $0.neumeID == "lyric-hyphen-event-0-event-1"
            }
        )
        XCTAssertEqual(
            hyphen.origin.y,
            firstSyllable.origin.y
                + (firstSyllable.fontSize - hyphen.fontSize) * 1.23 / 2,
            accuracy: 0.001,
            "The smaller hyphen should be vertically centered in the lyric line."
        )
        XCTAssertFalse(
            layout.lyrics.contains {
                $0.neumeID == "lyric-hyphen-event-1-event-2"
            },
            "A GABC word space must not receive a lyric hyphen."
        )
    }

    func testNearbyGABCFragmentsJoinWithoutAutomaticHyphens() throws {
        let fragments = ["Qui", "fe", "ci", "t cæ", "lu", "m e", "t te", "rram."]
        let timeline = ChantTimeline(
            events: fragments.enumerated().map { index, fragment in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: fragment,
                    relativePitch: index == fragments.count - 1 ? -2 : 0
                )
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: compact-fragments; %% (c3) R/.() Qui(h) fe(h)ci(h)t cæ(h)lu(h)m e(h)t te(h)rram.(f.) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 760)

        XCTAssertFalse(
            layout.lyrics.contains { $0.text == "-" },
            "Adjacent musical attachments should read as continuous words, including et rather than e-t."
        )
        let fragmentBeforeT = try XCTUnwrap(
            layout.lyrics.first { $0.neumeID == "event-5" }
        )
        let fragmentBeginningWithT = try XCTUnwrap(
            layout.lyrics.first { $0.neumeID == "event-6" }
        )
        XCTAssertLessThanOrEqual(
            fragmentBeginningWithT.origin.x
                - (fragmentBeforeT.origin.x + fragmentBeforeT.width),
            2,
            "The e and t in et should remain visually joined."
        )
    }

    func testReferencePrecesUseConnectorsOnlyWhereMusicalSpacingNeedsThem() throws {
        let fragments = [
            "De", "us", "in", "ad", "ju", "tó", "ri", "um", "me", "um",
            "in", "tén", "de."
        ]
        let timeline = ChantTimeline(
            events: fragments.enumerated().map { index, fragment in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: fragment,
                    relativePitch: 0
                )
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: reference-preces; %% (c3) V/.() De(h)us(h) ✠(,) in(h) ad(h)ju(h)tó(i)ri(h)um(h) me(h)um(h) in(h)tén(g)de.(h.) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 760)
        let actualHyphenIDs = Set(
            layout.lyrics.filter { $0.text == "-" }.map(\.neumeID)
        )

        XCTAssertEqual(
            actualHyphenIDs,
            Set([
                "lyric-hyphen-event-0-event-1",
                "lyric-hyphen-event-6-event-7",
                "lyric-hyphen-event-8-event-9"
            ]),
            "Match Exsurge's De-us, adjutóri-um, and me-um connectors without hyphenating every syllable."
        )

        let adjutoriumFragments = [
            "A", "dju", "tó", "ri", "u", "m nó", "strum", "i", "n nó",
            "mi", "ne", "Dó", "mi", "ni."
        ]
        let adjutoriumTimeline = ChantTimeline(
            events: adjutoriumFragments.enumerated().map { index, fragment in
                ChantEvent(
                    id: "adjutorium-event-\(index)",
                    phraseID: "phrase-1",
                    syllableID: "adjutorium-syllable-\(index)",
                    syllable: fragment,
                    relativePitch: 0
                )
            }
        )
        let adjutoriumScore = try GregorianScoreParser.parse(
            gabc: "name: reference-adjutorium; %% (c3) V/.() A(h)dju(h)tó(h)ri(h)u(h)m nó(h)strum(h) ✠(,) i(h)n nó(h)mi(h)ne(h) Dó(h)mi(h)ni.(f.) (::)",
            timeline: adjutoriumTimeline
        )
        let adjutoriumLayout = GregorianEngravingLayoutEngine().layout(
            score: adjutoriumScore,
            width: 760
        )

        XCTAssertEqual(
            Set(adjutoriumLayout.lyrics.filter { $0.text == "-" }.map(\.neumeID)),
            Set(["lyric-hyphen-adjutorium-event-3-adjutorium-event-4"]),
            "Match Exsurge's single adjutóri-um connector."
        )
    }

    func testReferenceDoxologyRetainsItsSelectiveConnectors() throws {
        let fragments = [
            "Gló", "ri", "a", "Pa", "tri,", "et", "Fí", "li", "o,", "et",
            "Spi", "rí", "tu", "i", "San", "cto.", "Sic", "ut", "e", "rat",
            "in", "prin", "cí", "pi", "o,", "et", "nunc,"
        ]
        let timeline = ChantTimeline(
            events: fragments.enumerated().map { index, fragment in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: fragment,
                    relativePitch: 0
                )
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: reference-doxology; %% (c3) Gló(h)ri(h)a(h) Pa(h)tri,(h) et(h) Fí(h)li(h)o,(h) et(h) Spi(h)rí(h)tu(h)i(h) San(g)cto.(h.) (:) Sic(h)ut(h) e(h)rat(h) in(h) prin(h)cí(h)pi(h)o,(h) et(h) nunc,(h) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 760)
        let actualHyphenIDs = Set(
            layout.lyrics.filter { $0.text == "-" }.map(\.neumeID)
        )
        let expectedReferenceConnectors = Set([
            "lyric-hyphen-event-1-event-2",   // Glóri-a
            "lyric-hyphen-event-6-event-7",   // Fí-li-o
            "lyric-hyphen-event-7-event-8",
            "lyric-hyphen-event-12-event-13", // Spíritu-i
            "lyric-hyphen-event-23-event-24"  // princípi-o
        ])

        XCTAssertTrue(
            expectedReferenceConnectors.isSubset(of: actualHyphenIDs),
            "Missing reference connectors: \(expectedReferenceConnectors.subtracting(actualHyphenIDs))"
        )
        XCTAssertFalse(
            actualHyphenIDs.contains("lyric-hyphen-event-0-event-1"),
            "Glóri should remain joined before the selective ri-a connector."
        )
        XCTAssertFalse(
            actualHyphenIDs.contains("lyric-hyphen-event-18-event-19"),
            "The compact e and rat fragments should read as erat, matching the reference engraving."
        )
    }

    func testAutomaticHyphenMarksAWordContinuedOnTheNextStaff() throws {
        let syllables = [
            "Su", "per", "ca", "li", "fra", "gi", "lis", "ti",
            "ce", "ex", "pi", "a", "li", "do", "cious"
        ]
        let timeline = ChantTimeline(
            events: syllables.enumerated().map { index, syllable in
                ChantEvent(
                    id: "event-\(index)",
                    phraseID: "phrase-0",
                    syllableID: "syllable-\(index)",
                    syllable: syllable,
                    relativePitch: index % 5
                )
            }
        )
        let body = zip(syllables, Array("fghijifghijifgh"))
            .map { "\($0.0)(\($0.1))" }
            .joined()
        let score = try GregorianScoreParser.parse(
            gabc: "name: line-end-hyphen; %% (c4) \(body) (::)",
            timeline: timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 240)
        let neumesByID = Dictionary(uniqueKeysWithValues: layout.neumes.map { ($0.id, $0) })
        let splitPair = try XCTUnwrap(
            zip(score.neumes, score.neumes.dropFirst()).first { previous, next in
                guard let previousPlacement = neumesByID[previous.id],
                      let nextPlacement = neumesByID[next.id] else {
                    return false
                }
                return previousPlacement.lineIndex != nextPlacement.lineIndex
                    && !next.startsWord
            }
        )

        let precedingLyric = try XCTUnwrap(
            layout.lyrics.first { $0.neumeID == splitPair.0.id }
        )
        let hyphen = try XCTUnwrap(
            layout.lyrics.first {
                $0.neumeID
                    == "lyric-hyphen-\(splitPair.0.id)-\(splitPair.1.id)"
            }
        )
        XCTAssertEqual(
            hyphen.origin.y,
            precedingLyric.origin.y
                + (precedingLyric.fontSize - hyphen.fontSize) * 1.23 / 2,
            accuracy: 0.001,
            "A line-end hyphen should be vertically centered in the lyric line."
        )
    }

    func testBundledSalveReginaUsesOnlyNecessaryAutomaticLyricHyphens() async throws {
        let databaseURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "base-office",
                withExtension: "sqlite",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "base-office", withExtension: "sqlite")
        )
        let repository = try SQLiteContentRepository(databaseURL: databaseURL)
        let office = try await repository.office(
            on: LocalDay(year: 2026, month: 7, day: 25),
            hour: .compline
        )
        let chant = try XCTUnwrap(
            office.sections.compactMap(\.chant).first {
                $0.incipit.hasPrefix("Salve, Regína")
            }
        )
        let score = try GregorianScoreParser.parse(
            gabc: chant.gabc,
            timeline: chant.timeline
        )
        let layout = GregorianEngravingLayoutEngine().layout(
            score: score,
            width: 390,
            openingLabel: chant.mode
        )
        var eligibleHyphenIDs: [String] = []
        var previousLyricNeume: GregorianNeume?
        var lyricMarkInterruptedWord = false
        for element in score.elements {
            switch element {
            case .lyricMark:
                lyricMarkInterruptedWord = true
            case let .neume(next) where !next.lyric.isEmpty:
                if let previous = previousLyricNeume,
                   !lyricMarkInterruptedWord,
                   !next.startsWord,
                   previous.syllableID != next.syllableID,
                   !previous.lyric.hasSuffix("-"),
                   !next.lyric.hasPrefix("-") {
                    eligibleHyphenIDs.append(
                        "lyric-hyphen-\(previous.id)-\(next.id)"
                    )
                }
                previousLyricNeume = next
                lyricMarkInterruptedWord = false
            default:
                break
            }
        }
        let actualHyphenIDs = Set(
            layout.lyrics
                .filter { $0.text == "-" }
                .map(\.neumeID)
        )
        let lyricNeumes = score.neumes.filter { !$0.lyric.isEmpty }
        let referenceConnectorPairs = [
            ("Sal", "ve,"), ("gí", "na,"), ("di", "ae :"),
            ("Vi", "ta,"), ("cé", "do,"), ("má", "mus,"),
            ("su", "les,"), ("li", "i"), ("spi", "rá"),
            ("rá", "mus,"), ("flen", "tes"), ("val", "le."),
            ("E", "ia"), ("cá", "ta"), ("tu", "os"),
            ("dí", "ctum"), ("tu", "i,"), ("sí", "li"),
            ("li", "um"), ("cle", "mens :"), ("pi", "a :"),
            ("Ma", "rí"), ("rí", "a.")
        ]
        let referenceConnectorIDs = try Set(referenceConnectorPairs.map { pair in
            let adjacent = try XCTUnwrap(
                zip(lyricNeumes, lyricNeumes.dropFirst()).first {
                    $0.0.lyric == pair.0 && $0.1.lyric == pair.1
                },
                "Missing Salve Regina syllable pair \(pair.0)|\(pair.1)"
            )
            return "lyric-hyphen-\(adjacent.0.id)-\(adjacent.1.id)"
        })
        let eligibleHyphenIDSet = Set(eligibleHyphenIDs)

        XCTAssertGreaterThan(
            eligibleHyphenIDs.count,
            20,
            "The bundled Salve Regina should exercise many visible syllable boundaries."
        )
        XCTAssertTrue(
            actualHyphenIDs.isSubset(of: eligibleHyphenIDSet),
            "Automatic hyphens must only mark encoded within-word boundaries."
        )
        XCTAssertFalse(
            actualHyphenIDs.isEmpty,
            "Wide musical gaps and staff continuations should retain necessary hyphens."
        )
        XCTAssertTrue(
            referenceConnectorIDs.isSubset(of: actualHyphenIDs),
            "Missing Salve Regina connectors: \(referenceConnectorIDs.subtracting(actualHyphenIDs))"
        )
        XCTAssertLessThan(
            actualHyphenIDs.count,
            eligibleHyphenIDs.count,
            "Compact syllable groups should join without a hyphen."
        )
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
