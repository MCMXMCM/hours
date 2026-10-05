import HoursCore
@testable import Hours
import XCTest

@MainActor
final class ChantGuideTests: XCTestCase {
    func testEveryBundledExampleHasExactNotationAndAnnotationMapping() throws {
        let doc = try ChantGuideDocument.load()
        XCTAssertEqual(doc.sections.count, 10)
        XCTAssertEqual(doc.examples.count, 35)
        for example in doc.examples {
            for variant in example.variants {
                let score = variant.score
                let parsed = try GregorianScoreParser.parse(gabc: score.gabc, timeline: score.timeline)
                XCTAssertEqual(parsed.eventIDs, score.timeline.events.map(\.id), score.id)
                for annotation in variant.annotations {
                    XCTAssertTrue(Set(annotation.eventIDs).isSubset(of: Set(parsed.eventIDs)), score.id)
                }
                for width in [272.0, 354.0, 712.0] {
                    for lyricScale in [1.0, 2.05] {
                        let layout = GregorianEngravingLayoutEngine().layout(score: parsed, width: width,
                            metrics: GregorianLayoutMetrics(notationScale: min(1.6, lyricScale), lyricScale: lyricScale))
                        XCTAssertTrue(layout.size.height.isFinite && layout.size.height > 0, score.id)
                        XCTAssertEqual(Set(layout.events.map(\.eventID)), Set(parsed.eventIDs), score.id)
                        for event in layout.events {
                            XCTAssertTrue(event.frame.minX >= -1 && event.frame.maxX <= width + 1,
                                          "\(score.id): \(event.frame) exceeds \(width)")
                        }
                    }
                }
            }
        }
    }

    func testClefComparisonsPreservePitchAndSolfege() throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("clef-equivalence"))
        let expected = example.variants[0].score.timeline.events.map { CantorGuideSynthesizer.semitoneOffset(for: $0) }
        for variant in example.variants {
            XCTAssertEqual(variant.score.timeline.events.map { CantorGuideSynthesizer.semitoneOffset(for: $0) }, expected)
            XCTAssertEqual(variant.score.timeline.events.map { ChantGuideSolfege.name($0, score: variant.score) }, ["Do", "Re", "Mi", "Re", "Do"])
        }
    }

    func testCClefPositionsNameEveryLineAndSpace() throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("clef-staff-positions"))
        let expected = [
            ["La", "Ti", "Do", "Re", "Mi", "Fa", "Sol"],
            ["Fa", "Sol", "La", "Ti", "Do", "Re", "Mi"],
            ["Re", "Mi", "Fa", "Sol", "La", "Ti", "Do"]
        ]
        XCTAssertEqual(example.variants.count, 3)
        for (index, variant) in example.variants.enumerated() {
            let score = variant.score
            XCTAssertEqual(score.timeline.events.map(\.relativePitch), [-4, -3, -2, -1, 0, 1, 2])
            XCTAssertEqual(score.timeline.events.map { ChantGuideSolfege.name($0, score: score) }, expected[index])
            XCTAssertEqual(score.timeline.events.map(\.syllable), expected[index])
            XCTAssertTrue(score.timeline.events.allSatisfy { $0.clef?.line == index + 2 })
        }
    }

    func testPsalmToneVersesMatchThePrintedFormulas() throws {
        let doc = try ChantGuideDocument.load()
        func solfege(_ id: String) throws -> [String] {
            let score = try XCTUnwrap(doc.example(id)?.variants.first?.score)
            return score.timeline.events.map { ChantGuideSolfege.name($0, score: score) }
        }
        // Liber Usualis (1961), Arabic pp. 117, 133: tone VIII, ending G.
        XCTAssertEqual(try solfege("tone-eight-g"), [
            "Sol", "La", "Do", "Do", "Do", "Do", "Do", "Do", "Re", "Do",
            "Do", "Do", "Do", "Ti", "Do", "La", "Sol"
        ])
        // Arabic pp. 113, 128: tone I, ending a³; the mediation alone has Ti-flat.
        XCTAssertEqual(try solfege("tone-one-a3"), [
            "Fa", "Sol", "La", "La", "La", "La", "Ti♭", "La", "La", "Sol", "La",
            "La", "La", "La", "Sol", "Fa", "Sol", "La", "Sol", "La"
        ])
        let endings = try XCTUnwrap(doc.example("tone-one-endings"))
        XCTAssertEqual(endings.variants.map { $0.score.timeline.events.count }, [7, 8, 9])
        for variant in endings.variants {
            let parsed = try GregorianScoreParser.parse(gabc: variant.score.gabc, timeline: variant.score.timeline)
            let expectedGroups = variant.id.hasSuffix("-a3") ? 2 : variant.id.hasSuffix("-a2") ? 1 : 0
            XCTAssertEqual(parsed.neumes.filter { $0.form == .podatus }.count, expectedGroups)
            XCTAssertEqual(variant.score.timeline.events.last.map {
                ChantGuideSolfege.name($0, score: variant.score)
            }, "La")
        }
        let vowels = try XCTUnwrap(doc.example("tone-euouae"))
        for variant in vowels.variants {
            XCTAssertEqual(Set(variant.score.timeline.events.map(\.syllableID)).count, 6)
        }
        XCTAssertEqual(vowels.variants.map { $0.score.timeline.events.count }, [6, 8])
    }

    func testTaughtNeumeFormsAndRepeatedNoteCounts() throws {
        let doc = try ChantGuideDocument.load()
        for (id, form) in [("podatus", GregorianNeumeForm.podatus), ("clivis", .clivis),
                           ("scandicus", .scandicus), ("climacus", .climacus),
                           ("torculus", .torculus), ("porrectus", .porrectus)] {
            let score = try XCTUnwrap(doc.example(id)?.variants.first?.score)
            let parsed = try GregorianScoreParser.parse(gabc: score.gabc, timeline: score.timeline)
            XCTAssertEqual(parsed.neumes.first?.form, form, id)
        }
        let repeated = try XCTUnwrap(doc.example("repeated-notes"))
        XCTAssertEqual(repeated.variants.map { $0.score.timeline.events.count }, [2, 2, 3, 4])
    }

    func testTeachingTimingMatchesDotsQuilismaAndSalicus() throws {
        let doc = try ChantGuideDocument.load()
        func durations(_ example: String, _ suffix: String = "main") throws -> [Double] {
            let score = try XCTUnwrap(doc.example(example)?.variants.first { $0.id.hasSuffix("-" + suffix) }?.score)
            return CantorGuideSynthesizer.performance(for: score.timeline.events, in: score).map(\.durationWeight)
        }
        XCTAssertEqual(try durations("rhythmic-signs", "plain"), [1, 1, 1])
        XCTAssertEqual(try durations("rhythmic-signs", "dot"), [1, 2, 1])
        XCTAssertEqual(try durations("rhythmic-signs", "vertical"), [1, 1, 1])
        XCTAssertEqual(try durations("quilisma"), [1.8, 1, 1])
        XCTAssertEqual(try durations("salicus", "salicus"), [1, 1.8, 1])
    }

    func testAccidentalsResetAtNewWord() throws {
        let score = try XCTUnwrap(ChantGuideDocument.load().example("accidentals")?.variants.last?.score)
        let pitches = score.timeline.events.map { CantorGuideSynthesizer.semitoneOffset(for: $0) }
        XCTAssertEqual(pitches[0], pitches[1])
        XCTAssertEqual(pitches[2], pitches[1] + 1)
    }

    func testFormulaIsNotAnExtraAudioEvent() throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("cadence-syllables"))
        XCTAssertEqual(example.variants.map { $0.score.timeline.events.count }, [5, 6])
        for variant in example.variants {
            XCTAssertEqual(variant.formula?.filter(\.optional).count, 1)
        }
    }

    func testViewportKeepsVisiblePlayingExampleAndOtherwiseFindsCenter() {
        let viewport = CGRect(x: 0, y: 100, width: 350, height: 500)
        let frames = ["first": CGRect(x: 0, y: -90, width: 350, height: 220),
                      "second": CGRect(x: 0, y: 250, width: 350, height: 200),
                      "third": CGRect(x: 0, y: 650, width: 350, height: 200)]
        XCTAssertEqual(ChantGuideViewport.target(frames: frames, viewport: viewport, playingID: nil), "second")
        XCTAssertEqual(ChantGuideViewport.target(frames: frames, viewport: viewport, playingID: "first"), "first")
        XCTAssertEqual(ChantGuideViewport.target(frames: frames, viewport: viewport, playingID: "third"), "second")
        XCTAssertNil(ChantGuideViewport.target(frames: frames, viewport: .zero, playingID: nil))
        XCTAssertNil(ChantGuideViewport.target(frames: ["third": frames["third"]!], viewport: viewport, playingID: nil))
    }

    func testPreparingComparisonsNeverStartsPlayback() throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("clef-equivalence"))
        let controller = ChantPlaybackController()
        for variant in example.variants {
            controller.prepare(score: variant.score, pitchReference: example.pitchReference)
            XCTAssertFalse(controller.isPlaying)
            XCTAssertNil(controller.currentEventID)
            XCTAssertEqual(controller.preparedScoreID, variant.score.id)
        }
    }
}
