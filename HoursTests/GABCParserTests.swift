import XCTest
@testable import HoursCore

final class GregorianScoreParserTests: XCTestCase {
    private struct SharedFixture: Decodable {
        let name: String
        let scoreID: String
        let gabc: String
        let eventCount: Int
        let neumeSizes: [Int]
    }

    func testSharedCompilerEngravingFixtures() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "gabc-engraving-fixtures",
                withExtension: "json"
            )
        )
        let fixtures = try JSONDecoder().decode(
            [SharedFixture].self,
            from: Data(contentsOf: url)
        )

        for fixture in fixtures {
            var noteIndex = 0
            var events: [ChantEvent] = []
            for (syllableIndex, neumeSize) in fixture.neumeSizes.enumerated() {
                for _ in 0..<neumeSize {
                    events.append(
                        ChantEvent(
                            id: "\(fixture.scoreID)-note-\(noteIndex)",
                            phraseID: "\(fixture.scoreID)-phrase-0",
                            syllableID: "\(fixture.scoreID)-syllable-\(syllableIndex)",
                            syllable: "fixture",
                            relativePitch: 0
                        )
                    )
                    noteIndex += 1
                }
            }
            let score = try GregorianScoreParser.parse(
                gabc: fixture.gabc,
                timeline: ChantTimeline(events: events)
            )
            XCTAssertEqual(score.eventIDs, events.map(\.id), fixture.name)
            XCTAssertEqual(score.neumes.map { $0.notes.count }, fixture.neumeSizes, fixture.name)
        }
    }

    func testOnlyRAndR0MarkAHollowNote() throws {
        // r and r0 are hollow notes; r1 to r5 are signs written above a note.
        let gabc = "name: test; %% (c3) no(hr1)bis(hr) ló(hr0)rum(h.r3) (::)"
        let timeline = makeTimeline(pitches: [9, 9, 9, 9], syllables: ["no", "bis", "ló", "rum"])
        let score = try GregorianScoreParser.parse(gabc: gabc, timeline: timeline)
        XCTAssertEqual(score.neumes.flatMap { $0.notes.map(\.isCavum) }, [false, true, true, false])
    }

    func testMapsCompilerEventsAndPreservesNeumeGrouping() throws {
        let gabc = "name: test; %% (c4) Ky(fg_)ri(h.w)e(ixj~) (;) test(k) (::)"
        let timeline = makeTimeline(
            pitches: [5, 6, 7, 9, 10],
            syllables: ["Ky", "Ky", "ri", "e", "test"]
        )

        let score = try GregorianScoreParser.parse(gabc: gabc, timeline: timeline)
        XCTAssertEqual(score.eventIDs, timeline.events.map(\.id))
        XCTAssertEqual(score.neumes.count, 4)
        XCTAssertEqual(score.neumes.first?.notes.count, 2)
        XCTAssertEqual(score.neumes.first?.notes.last?.hasEpisema, true)
        XCTAssertEqual(score.neumes[1].notes.first?.shape, .quilisma)
        XCTAssertEqual(score.neumes[1].notes.first?.hasMora, true)
        XCTAssertEqual(score.neumes[2].notes.first?.shape, .liquescent)
        let accidental = try XCTUnwrap(
            score.elements.compactMap { element -> GregorianAccidentalMark? in
                guard case let .accidental(accidental) = element else { return nil }
                return accidental
            }.first
        )
        XCTAssertEqual(accidental.kind, .flat)
        XCTAssertEqual(accidental.pitch, 8)

        let clefs = score.elements.compactMap { element -> GregorianClef? in
            guard case let .clef(clef) = element else { return nil }
            return clef
        }
        XCTAssertEqual(clefs, [GregorianClef(kind: .c, line: 4)])

        let divisions = score.elements.compactMap { element -> GregorianDivision? in
            guard case let .division(division) = element else { return nil }
            return division
        }
        XCTAssertEqual(divisions, [.minor, .final])
    }

    func testInManusAccidentalIsNotEngravedOrMappedAsAnExtraNote() throws {
        let timeline = makeTimeline(
            pitches: [7, 7, 7, 8, 7],
            syllables: ["Red", "e", "mí", "mí", "sti"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: In manus; %% (c4) Red(h)e(h)mí(ixhi)sti(h) (::)",
            timeline: timeline
        )

        let mi = try XCTUnwrap(score.neumes.first(where: { $0.lyric == "mí" }))
        XCTAssertEqual(mi.notes.map(\.pitch), [7, 8])
        XCTAssertEqual(mi.form, .podatus)
        let accidental = try XCTUnwrap(
            score.elements.compactMap { element -> GregorianAccidentalMark? in
                guard case let .accidental(accidental) = element else { return nil }
                return accidental
            }.first
        )
        XCTAssertEqual(accidental.kind, .flat)
        XCTAssertEqual(accidental.pitch, 8)

        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        XCTAssertTrue(
            layout.glyphs.contains { $0.kind == .catalog(.podatusLower) }
        )
        XCTAssertTrue(
            layout.glyphs.contains { $0.kind == .catalog(.podatusUpper) }
        )
        XCTAssertFalse(
            layout.glyphs.contains {
                [.porrectus1, .porrectus2, .porrectus3, .porrectus4]
                    .contains($0.kind.catalogName)
            }
        )
    }

    func testClefAndDivisionsDoNotConsumeTimelineEvents() throws {
        let timeline = makeTimeline(pitches: [5, 6, 7], syllables: ["Ky", "ri", "e"])
        let score = try GregorianScoreParser.parse(
            gabc: "name: clef; %% Ky(c4f)ri(g)e.(h.) (::)",
            timeline: timeline
        )
        XCTAssertEqual(score.eventIDs, timeline.events.map(\.id))
        XCTAssertEqual(score.neumes.map(\.lyric), ["Ky", "ri", "e."])
    }

    func testFlatCClefDoesNotBecomeTimelineNotesAndIsEngraved() throws {
        let timeline = makeTimeline(pitches: [5, 6], syllables: ["Ky", "Ky"])
        let score = try GregorianScoreParser.parse(
            gabc: "name: flat clef; %% (cb4) Ky(fg) (::)",
            timeline: timeline
        )

        XCTAssertEqual(score.eventIDs, timeline.events.map(\.id))
        let clef = try XCTUnwrap(score.elements.compactMap { element -> GregorianClef? in
            guard case let .clef(clef) = element else { return nil }
            return clef
        }.first)
        XCTAssertEqual(clef, GregorianClef(kind: .c, line: 4, flattensB: true))

        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        XCTAssertTrue(layout.glyphs.contains { $0.kind == .flat })
    }

    func testClassifiesNamedNeumeFormsFromPitchContours() throws {
        let timeline = makeTimeline(
            pitches: Array(0..<10),
            syllables: ["po", "po", "cli", "cli", "scan", "scan", "scan", "tor", "tor", "tor"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: forms; %% (c4) po(fg) cli(gf) scan(fgh) tor(fhg) (::)",
            timeline: timeline
        )

        XCTAssertEqual(score.neumes.map(\.form), [.podatus, .clivis, .scandicus, .torculus])
    }

    func testPreservesDetailedNoteModifiers() throws {
        let timeline = makeTimeline(pitches: [5], syllables: ["Ky"])
        let score = try GregorianScoreParser.parse(
            gabc: "name: modifiers; %% (c4) Ky(f.._0#') (::)",
            timeline: timeline
        )
        let note = try XCTUnwrap(score.neumes.first?.notes.first)

        XCTAssertEqual(note.accidental, .sharp)
        XCTAssertEqual(note.moraCount, 2)
        XCTAssertEqual(note.episemaPosition, .below)
        XCTAssertTrue(note.hasIctus)
    }

    func testRemovesPsalmTonePointingDelimitersFromLyrics() throws {
        let timeline = makeTimeline(
            pitches: Array(0..<8),
            syllables: ["ta", "ber", "ná", "_cu_", "_la_", "*Ja*", "cob.", "*"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: Psalmus 86; %% (c4) ta(j)ber(j)ná(j)_cu_(h)_la_(j) *Ja*(k)cob.(j.) *(h) (::)",
            timeline: timeline
        )

        XCTAssertEqual(
            score.neumes.map(\.lyric),
            ["ta", "ber", "ná", "cu", "la", "Ja", "cob.", "*"]
        )
        XCTAssertEqual(
            score.neumes.map(\.lyricStyle),
            [
                .regular, .regular, .regular, .preparatory,
                .preparatory, .accented, .regular, .regular
            ]
        )
    }

    func testIgnoresGABCLineCommentsInsteadOfRenderingPercentSigns() throws {
        let timeline = makeTimeline(
            pitches: [7, 8],
            syllables: ["Hó", "die"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: Invitatorium; %% (c3)\r\n%\r\nHó(h)% source note\r\ndie(i) (::)",
            timeline: timeline
        )

        XCTAssertEqual(score.neumes.map(\.lyric), ["Hó", "die"])
        XCTAssertFalse(score.neumes.contains { $0.lyric.contains("%") })
        XCTAssertFalse(score.neumes.contains { $0.lyric.contains("source note") })
    }

    func testPreservesNoteLessLiturgicalAsteriskAsRubric() throws {
        let timeline = makeTimeline(
            pitches: [7, 6, 5],
            syllables: ["fac", "fac", "Dó"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: Psalmus 6; %% (c4) fac(gh) *()Dó(f) (::)",
            timeline: timeline
        )
        let mark = try XCTUnwrap(
            score.elements.compactMap { element -> GregorianLyricMark? in
                guard case let .lyricMark(mark) = element else { return nil }
                return mark
            }.first
        )

        XCTAssertEqual(mark.text, "*")
        XCTAssertEqual(mark.style, .rubric)
        XCTAssertTrue(mark.startsWord)
        XCTAssertEqual(score.neumes.map(\.lyric), ["fac", "Dó"])
        XCTAssertEqual(score.eventIDs, timeline.events.map(\.id))

        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        XCTAssertEqual(layout.lyrics.map(\.text), ["fac", "*", "Dó"])
        XCTAssertEqual(layout.lyrics.map(\.style), [.regular, .rubric, .regular])

        let fac = try XCTUnwrap(layout.lyrics.first { $0.text == "fac" })
        let asterisk = try XCTUnwrap(layout.lyrics.first { $0.text == "*" })
        let domine = try XCTUnwrap(layout.lyrics.first { $0.text == "Dó" })
        XCTAssertGreaterThan(
            asterisk.origin.x,
            fac.origin.x + fac.width
        )
        XCTAssertGreaterThan(
            domine.origin.x,
            asterisk.origin.x + asterisk.width
        )
    }

    func testProjectsCompleteLatinWithoutLosingWordBoundaries() throws {
        let timeline = makeTimeline(
            pitches: [5, 6, 7, 8, 9, 10, 9],
            syllables: ["Sal", "ve,", "Re", "gí", "na", "Dó", "mi"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: Salve; %% (c4) Sal(f)ve,(g) Re(h)gí(i)na(j) *()Dó(k)mi(j) (::)",
            timeline: timeline
        )

        XCTAssertEqual(score.lyricText, "Salve, Regína * Dómi")
    }

    func testUsesVersicleAndResponseGlyphsInsteadOfAsciiSlashes() throws {
        let timeline = makeTimeline(
            pitches: [5, 6],
            syllables: ["Jube", "Amen"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: fallback marks; %% (c4) V/.()Jube(f) R/.()Amen(g) (::)",
            timeline: timeline
        )
        let marks = score.elements.compactMap { element -> GregorianLyricMark? in
            guard case let .lyricMark(mark) = element else { return nil }
            return mark
        }

        XCTAssertEqual(marks.map(\.text), ["℣.", "℟."])
        XCTAssertEqual(marks.map(\.style), [.rubric, .rubric])

        let layout = GregorianEngravingLayoutEngine().layout(score: score, width: 390)
        XCTAssertEqual(layout.lyrics.map(\.text), ["℣.", "Jube", "℟.", "Amen"])
        XCTAssertFalse(layout.lyrics.contains { $0.text.contains("/") })
    }

    func testZeroSpaceBoundarySplitsNamedNeumesWithoutLosingLyricIdentity() throws {
        let timeline = makeTimeline(
            pitches: [5, 6, 7, 8],
            syllables: ["Ky", "Ky", "Ky", "Ky"]
        )
        let score = try GregorianScoreParser.parse(
            gabc: "name: boundary; %% (c4) Ky(fg!hi) (::)",
            timeline: timeline
        )

        XCTAssertEqual(score.neumes.count, 2)
        XCTAssertEqual(score.neumes.map(\.form), [.podatus, .podatus])
        XCTAssertEqual(score.neumes.map(\.lyric), ["Ky", ""])
        XCTAssertEqual(score.eventIDs, timeline.events.map(\.id))
    }

    func testTimelineMismatchIsAValidationFailure() {
        let timeline = makeTimeline(pitches: [5], syllables: ["Ky"])
        XCTAssertThrowsError(
            try GregorianScoreParser.parse(
                gabc: "name: mismatch; %% Ky(c4fg)",
                timeline: timeline
            )
        ) { error in
            guard case GregorianScoreParserError.tooManyNotationNotes = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnsupportedTokenIsAValidationFailure() {
        let timeline = makeTimeline(pitches: [5], syllables: ["Ky"])
        XCTAssertThrowsError(
            try GregorianScoreParser.parse(
                gabc: "name: unsupported; %% Ky(c4f?)",
                timeline: timeline
            )
        ) { error in
            guard case GregorianScoreParserError.unsupportedToken("?", _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCivilDateRoundTripDoesNotShiftAcrossLocalMidnight() throws {
        let day = LocalDay(year: 2026, month: 7, day: 23)
        XCTAssertEqual(LocalDay(try XCTUnwrap(day.date)), day)
    }

    private func makeTimeline(pitches: [Int], syllables: [String]) -> ChantTimeline {
        precondition(pitches.count == syllables.count)
        var syllableNumber = 0
        var previousSyllable: String?
        return ChantTimeline(
            events: zip(pitches, syllables).enumerated().map { index, pair in
                if pair.1 != previousSyllable {
                    syllableNumber += 1
                    previousSyllable = pair.1
                }
                return ChantEvent(
                    id: "fixture-note-\(index)",
                    phraseID: "fixture-phrase-0",
                    syllableID: "fixture-syllable-\(syllableNumber)",
                    syllable: pair.1,
                    relativePitch: pair.0 - 7
                )
            }
        )
    }
}
