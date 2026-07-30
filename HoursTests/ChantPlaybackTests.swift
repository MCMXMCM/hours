@preconcurrency import AVFoundation
import HoursCore
@testable import Hours
import XCTest

@MainActor
final class ChantPlaybackTests: XCTestCase {
    func testCantorGuideDefaultsToEightyFivePercentTempo() {
        let controller = ChantPlaybackController()

        XCTAssertEqual(controller.tempo, 0.85)
    }

    func testCantorGuideDismissesOnlyForADeliberateDownwardSwipe() {
        XCTAssertTrue(
            CantorGuideDismissal.shouldDismiss(
                translation: CGSize(width: 8, height: 96),
                predictedEndTranslation: CGSize(width: 10, height: 112)
            )
        )
        XCTAssertTrue(
            CantorGuideDismissal.shouldDismiss(
                translation: CGSize(width: 4, height: 48),
                predictedEndTranslation: CGSize(width: 5, height: 180)
            )
        )
        XCTAssertFalse(
            CantorGuideDismissal.shouldDismiss(
                translation: CGSize(width: 6, height: 40),
                predictedEndTranslation: CGSize(width: 8, height: 72)
            )
        )
        XCTAssertFalse(
            CantorGuideDismissal.shouldDismiss(
                translation: CGSize(width: 120, height: 90),
                predictedEndTranslation: CGSize(width: 160, height: 190)
            )
        )
    }

    func testCantorGuideTitleUsesPrayerLineForVersicleAndResponseMarkers() {
        func score(
            incipit: String,
            gabc: String,
            syllables: [String]
        ) -> ChantScore {
            let scoreID = "title-\(incipit)"
            let events = syllables.enumerated().map { index, syllable in
                ChantEvent(
                    id: "\(scoreID)-note-\(index)",
                    phraseID: "\(scoreID)-phrase",
                    syllableID: "\(scoreID)-syllable-\(index)",
                    syllable: syllable,
                    relativePitch: 0
                )
            }
            return ChantScore(
                id: scoreID,
                incipit: incipit,
                gabc: gabc,
                reviewStatus: .humanReviewed,
                provenance: ChantProvenance(
                    collection: "Test",
                    sourceBook: "Test",
                    license: "Test",
                    snapshot: "test"
                ),
                timeline: ChantTimeline(events: events)
            )
        }

        let versicle = score(
            incipit: "V/",
            gabc: """
            %% (c3)V/.() Ju(h)be(h) Dó(h)mi(h)ne(g) \
            be(h)ne(h)dí(h)ce(d)re.(d.) (::)
            """,
            syllables: [
                "Ju", "be", "Dó", "mi", "ne",
                "be", "ne", "dí", "ce", "re."
            ]
        )
        let response = score(
            incipit: "R/",
            gabc: "%% (c3)R/.() A(g.)men(h.) (::)",
            syllables: ["A", "men"]
        )

        XCTAssertEqual(
            CantorGuideTitle.text(for: versicle),
            "Jube Dómine benedícere."
        )
        XCTAssertEqual(
            CantorGuideTitle.text(for: response),
            "Amen"
        )
    }

    func testScholaPitchesAndRegistersMapToTheirSoundingOctaves() {
        XCTAssertEqual(
            CantorGuideSound.allCases.map(\.displayName),
            ["Organ", "Simple Tone"]
        )
        XCTAssertEqual(
            ScholaPitch.allCases.map(\.displayName),
            ["A", "B♭"]
        )
        XCTAssertEqual(
            ScholaPitch.allCases.map(\.semitoneOffset),
            [2, 3]
        )
        XCTAssertEqual(
            ChantRegister.allCases.map(\.displayName),
            ["Low", "High"]
        )
        XCTAssertEqual(
            ChantRegister.allCases.map(\.octaveOffset),
            [-12, 0]
        )

        let controller = ChantPlaybackController()
        XCTAssertEqual(controller.guideSound, .organ)
        XCTAssertEqual(controller.scholaPitch, .a)
        XCTAssertEqual(controller.chantRegister, .low)
        XCTAssertEqual(controller.targetDominantOffset, -10)

        let event = ChantEvent(
            id: "dominant",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0
        )
        let expected: [(ScholaPitch, ChantRegister, Double)] = [
            (.a, .low, 220),
            (.bFlat, .low, 233.081_88),
            (.a, .high, 440),
            (.bFlat, .high, 466.163_76)
        ]
        for (pitch, register, frequency) in expected {
            let targetOffset = pitch.semitoneOffset + register.octaveOffset
            XCTAssertEqual(
                CantorGuideSynthesizer.frequency(
                    for: event,
                    transposition: targetOffset
                ),
                frequency,
                accuracy: frequency * 0.000_3
            )
        }
    }

    func testRenderedDominantsStayWithinFiveCentsOfEveryScholaSetting() throws {
        let sampleRate = 48_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )
        let event = ChantEvent(
            id: "dominant",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0,
            durationWeight: 4
        )
        let expected: [(ScholaPitch, ChantRegister, Double)] = [
            (.a, .low, 220),
            (.bFlat, .low, 233.081_88),
            (.a, .high, 440),
            (.bFlat, .high, 466.163_76)
        ]

        for (pitch, register, expectedFrequency) in expected {
            let renderer = try makeOrganRenderer(format: format)
            let buffer = try renderer.render(
                performanceEvent: performanceEvent(
                    event,
                    startsPhrase: true,
                    endsPhrase: true
                ),
                tempo: 1,
                transposition:
                    pitch.semitoneOffset + register.octaveOffset,
                clef: .c3,
                register: register
            )
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            let start = Int(0.22 * sampleRate)
            let length = min(24_000, Int(buffer.frameLength) - start)
            var strongestCents = 0.0
            var strongestMagnitude = 0.0

            for step in -100...100 {
                let cents = Double(step) * 0.2
                let candidate =
                    expectedFrequency * pow(2, cents / 1_200)
                var real = 0.0
                var imaginary = 0.0
                for offset in 0..<length {
                    let angle =
                        2 * Double.pi * candidate * Double(offset)
                        / sampleRate
                    let value = Double(samples[start + offset])
                    real += value * cos(angle)
                    imaginary -= value * sin(angle)
                }
                let magnitude = hypot(real, imaginary)
                if magnitude > strongestMagnitude {
                    strongestMagnitude = magnitude
                    strongestCents = cents
                }
            }

            XCTAssertLessThan(
                abs(strongestCents),
                5,
                "\(pitch.displayName) \(register.displayName) was "
                    + "\(strongestCents) cents from its target."
            )
        }
    }

    func testJubeDomineUsesC3ClefIntervalsCenteredOnG4() {
        let staffSteps = [0, 0, 0, 0, -1, 0, 0, 0, -4, -4]
        let events = staffSteps.enumerated().map { index, staffStep in
            ChantEvent(
                id: "jube-\(index)",
                phraseID: "jube",
                syllableID: "jube-\(index)",
                syllable: "fixture",
                relativePitch: staffStep
            )
        }

        let transposition = CantorGuideSynthesizer.centeredTransposition(
            for: events,
            targetOffset: 0,
            clef: GABCClef(gabc: "(c3)")
        )
        let frequencies = events.map {
            CantorGuideSynthesizer.frequency(
                for: $0,
                transposition: transposition,
                clef: GABCClef(gabc: "(c3)")
            )
        }

        XCTAssertEqual(transposition, 0)
        XCTAssertEqual(frequencies[0], 392.0, accuracy: 0.01)
        XCTAssertEqual(frequencies[4], 369.99, accuracy: 0.01)
        XCTAssertEqual(frequencies[8], 261.63, accuracy: 0.01)
    }

    func testSelectedPitchCentersTheDominantRatherThanTheGABCLetterH() {
        let events = [
            ChantEvent(
                id: "intro",
                phraseID: "phrase",
                syllableID: "intro",
                syllable: "Intro",
                relativePitch: 0
            ),
            ChantEvent(
                id: "reciting-1",
                phraseID: "phrase",
                syllableID: "reciting-1",
                syllable: "reciting",
                relativePitch: 1
            ),
            ChantEvent(
                id: "reciting-2",
                phraseID: "phrase",
                syllableID: "reciting-2",
                syllable: "tone",
                relativePitch: 1
            )
        ]

        let transposition = CantorGuideSynthesizer.centeredTransposition(
            for: events,
            targetOffset:
                ScholaPitch.a.semitoneOffset
                + ChantRegister.low.octaveOffset
        )

        XCTAssertEqual(transposition, -12)
        XCTAssertEqual(
            CantorGuideSynthesizer.frequency(for: events[1], transposition: transposition),
            220.0,
            accuracy: 0.01
        )
    }

    func testGregorianStaffStepsAndFlatsMapToChromaticSemitones() {
        func event(_ staffStep: Int, modifiers: [ChantNotationModifier] = []) -> ChantEvent {
            ChantEvent(
                id: "note-\(staffStep)-\(modifiers.count)",
                phraseID: "phrase",
                syllableID: "syllable",
                syllable: "note",
                relativePitch: staffStep,
                modifiers: modifiers
            )
        }

        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: event(-4)), -7)
        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: event(-1)), -1)
        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: event(0)), 0)
        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: event(1)), 2)
        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: event(7)), 12)
        XCTAssertEqual(
            CantorGuideSynthesizer.semitoneOffset(for: event(2, modifiers: [.flat])),
            3
        )
        XCTAssertEqual(
            CantorGuideSynthesizer.semitoneOffset(for: event(0, modifiers: [.sharp])),
            1
        )
    }

    func testPitchMappingFollowsTheScoresClef() {
        let event = ChantEvent(
            id: "note",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "note",
            relativePitch: 0
        )

        XCTAssertEqual(GABCClef(gabc: "name: c3; %% (c3)").kind, .c)
        XCTAssertEqual(GABCClef(gabc: "name: c3; %% (c3)").line, 3)
        XCTAssertEqual(
            CantorGuideSynthesizer.semitoneOffset(
                for: event,
                clef: GABCClef(gabc: "name: c4; %% (c4)")
            ),
            -3
        )
        XCTAssertEqual(
            CantorGuideSynthesizer.semitoneOffset(
                for: event,
                clef: GABCClef(gabc: "name: f3; %% (f3)")
            ),
            5
        )
    }

    func testDecemberEightTimelineChangesFromC3ToC2() {
        let before = ChantEvent(
            id: "december-8-before",
            phraseID: "phrase",
            syllableID: "before",
            syllable: "María",
            relativePitch: 0,
            clef: ChantClef(kind: .c, line: 3)
        )
        let after = ChantEvent(
            id: "december-8-after",
            phraseID: "phrase",
            syllableID: "after",
            syllable: "grátia",
            relativePitch: 0,
            clef: ChantClef(kind: .c, line: 2)
        )

        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: before), 0)
        XCTAssertEqual(CantorGuideSynthesizer.semitoneOffset(for: after), 4)
    }

    func testControllerStartsPlaybackAndPublishesFirstEvent() async {
        let event = ChantEvent(
            id: "note-1",
            phraseID: "phrase-1",
            syllableID: "syllable-1",
            syllable: "Ky",
            relativePitch: 0,
            durationWeight: 4
        )
        let score = ChantScore(
            id: "score-1",
            incipit: "Kyrie",
            gabc: "(c4) Ky(f)rie(g)",
            reviewStatus: .humanReviewed,
            provenance: ChantProvenance(
                collection: "Test",
                sourceBook: "Test",
                license: "Test",
                snapshot: "test"
            ),
            timeline: ChantTimeline(events: [event])
        )
        let controller = ChantPlaybackController()
        defer { controller.stop() }

        controller.play(score: score)
        await Task.yield()

        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.currentEventID, event.id)
    }

    func testControllerAdvancesHighlightWhenAudioFinishesEvent() async throws {
        let first = ChantEvent(
            id: "note-1",
            phraseID: "phrase-1",
            syllableID: "syllable-1",
            syllable: "Ky",
            relativePitch: 0,
            durationWeight: 0.25
        )
        let second = ChantEvent(
            id: "note-2",
            phraseID: "phrase-1",
            syllableID: "syllable-2",
            syllable: "ri",
            relativePitch: 2,
            durationWeight: 4
        )
        let score = ChantScore(
            id: "score-1",
            incipit: "Kyrie",
            gabc: "(c4) Ky(f)ri(h)e(g)",
            reviewStatus: .humanReviewed,
            provenance: ChantProvenance(
                collection: "Test",
                sourceBook: "Test",
                license: "Test",
                snapshot: "test"
            ),
            timeline: ChantTimeline(events: [first, second])
        )
        let controller = ChantPlaybackController()
        defer { controller.stop() }

        controller.play(score: score)
        XCTAssertEqual(controller.currentEventID, first.id)

        for _ in 0..<50 where controller.currentEventID != second.id {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(controller.currentEventID, second.id)
    }

    func testSynthesizerProducesAudibleSamplesAtExpectedDuration() throws {
        let event = ChantEvent(
            id: "note-1",
            phraseID: "phrase-1",
            syllableID: "syllable-1",
            syllable: "Ky",
            relativePitch: 0
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        )

        let renderer = try makeOrganRenderer(format: format)
        let buffer = try renderer.render(
            performanceEvent: performanceEvent(
                event,
                startsPhrase: true,
                endsPhrase: true
            ),
            tempo: 1,
            transposition: 0,
            clef: .c3,
            register: .high
        )

        XCTAssertEqual(buffer.frameLength, 3_040)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength))
            .map { abs(samples[$0]) }
            .max() ?? 0
        XCTAssertGreaterThan(peak, 0.03)
    }

    func testSynthesizerClampsInvalidTempoToFiniteDuration() {
        let event = ChantEvent(
            id: "note-1",
            phraseID: "phrase-1",
            syllableID: "syllable-1",
            syllable: "Ky",
            relativePitch: 0
        )

        XCTAssertEqual(
            CantorGuideSynthesizer.seconds(for: event, tempo: 0),
            3.8,
            accuracy: 0.000_1
        )
    }

    func testSynthesizerProducesMonoSafeStereoOutput() throws {
        let event = ChantEvent(
            id: "note-1",
            phraseID: "phrase-1",
            syllableID: "syllable-1",
            syllable: "Ky",
            relativePitch: 0
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 2)
        )

        let renderer = try makeOrganRenderer(format: format)
        let buffer = try renderer.render(
            performanceEvent: performanceEvent(
                event,
                startsPhrase: true,
                endsPhrase: true
            ),
            tempo: 1,
            transposition: 0,
            clef: .c3,
            register: .high
        )
        let channels = try XCTUnwrap(buffer.floatChannelData)

        let frameCount = Int(buffer.frameLength)
        let difference = (0..<frameCount).reduce(0.0) {
            $0 + Double(abs(channels[0][$1] - channels[1][$1]))
        } / Double(frameCount)
        let leftPeak = (0..<frameCount).map { abs(channels[0][$0]) }.max() ?? 0
        let rightPeak = (0..<frameCount).map { abs(channels[1][$0]) }.max() ?? 0
        let monoPeak = (0..<frameCount)
            .map { abs((channels[0][$0] + channels[1][$0]) * 0.5) }
            .max() ?? 0

        XCTAssertGreaterThan(difference, 0.000_1)
        XCTAssertGreaterThan(leftPeak, 0.03)
        XCTAssertGreaterThan(rightPeak, 0.03)
        XCTAssertGreaterThan(monoPeak, 0.03)
        XCTAssertLessThan(leftPeak, 1)
        XCTAssertLessThan(rightPeak, 1)
        XCTAssertLessThan(monoPeak, 1)
    }

    func testSynthesizerIsDeterministicAndNumericallySafe() throws {
        let firstEvent = ChantEvent(
            id: "note-1",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0
        )
        let secondEvent = ChantEvent(
            id: "note-2",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 2
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        )

        func renderSequence() throws -> [Float] {
            let renderer = try makeOrganRenderer(format: format)
            let first = try renderer.render(
                performanceEvent: performanceEvent(
                    firstEvent,
                    startsPhrase: true
                ),
                tempo: 1,
                transposition: -10,
                clef: .c3,
                register: .low
            )
            let second = try renderer.render(
                performanceEvent: performanceEvent(
                    secondEvent,
                    endsPhrase: true,
                    startsSyllable: false
                ),
                tempo: 1,
                transposition: -10,
                clef: .c3,
                register: .low
            )
            var renderedSamples: [Float] = []
            for buffer in [first, second] {
                guard let samples = buffer.floatChannelData?[0] else {
                    continue
                }
                renderedSamples.append(
                    contentsOf: (0..<Int(buffer.frameLength))
                        .map { samples[$0] }
                )
            }
            return renderedSamples
        }

        let firstSamples = try renderSequence()
        let secondSamples = try renderSequence()

        var mean = 0.0
        var peak = 0.0
        XCTAssertEqual(firstSamples.count, secondSamples.count)
        for frame in firstSamples.indices {
            let sample = Double(firstSamples[frame])
            XCTAssertTrue(sample.isFinite)
            XCTAssertEqual(firstSamples[frame], secondSamples[frame])
            mean += sample
            peak = max(peak, abs(sample))
        }
        mean /= Double(firstSamples.count)

        XCTAssertLessThan(abs(mean), 0.01)
        XCTAssertGreaterThan(peak, 0.04)
        XCTAssertLessThan(peak, 0.91)
    }

    func testOrganAndSimpleToneHaveStrongSafeOutputLevels() throws {
        let event = ChantEvent(
            id: "level",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0,
            durationWeight: 2
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        let performanceEvent = performanceEvent(
            event,
            startsPhrase: true,
            endsPhrase: true
        )
        let organ = try makeOrganRenderer(format: format)
        let simpleTone = PitchPipeRenderer(format: format)
        let organBuffer = try organ.render(
            performanceEvent: performanceEvent,
            tempo: 0.85,
            transposition: -10,
            clef: .c3,
            register: .low
        )
        let simpleToneBuffer = try simpleTone.render(
            performanceEvent: performanceEvent,
            tempo: 0.85,
            transposition: -10,
            clef: .c3,
            register: .low
        )

        func peak(in buffer: AVAudioPCMBuffer) throws -> Float {
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            return (0..<Int(buffer.frameLength))
                .map { abs(samples[$0]) }
                .max() ?? 0
        }

        let organPeak = try peak(in: organBuffer)
        let simpleTonePeak = try peak(in: simpleToneBuffer)
        XCTAssertGreaterThan(organPeak, 0.12)
        XCTAssertGreaterThan(simpleTonePeak, 0.35)
        XCTAssertLessThanOrEqual(organPeak, 0.9)
        XCTAssertLessThan(simpleTonePeak, 0.7)
    }

    func testMutedOrganRetainsSubtleHarmonicsBeyondTheFundamental() throws {
        let event = ChantEvent(
            id: "note-1",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0,
            durationWeight: 3
        )
        let sampleRate = 16_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )
        let renderer = try makeOrganRenderer(format: format)
        let buffer = try renderer.render(
            performanceEvent: performanceEvent(
                event,
                startsPhrase: true,
                endsPhrase: true
            ),
            tempo: 1,
            transposition: -10,
            clef: .c3,
            register: .low
        )
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let start = Int(0.25 * sampleRate)
        let length = min(4_096, Int(buffer.frameLength) - start)

        func magnitude(at frequency: Double) -> Double {
            var real = 0.0
            var imaginary = 0.0
            for offset in 0..<length {
                let angle =
                    2 * Double.pi * frequency * Double(offset) / sampleRate
                let value = Double(samples[start + offset])
                real += value * cos(angle)
                imaginary -= value * sin(angle)
            }
            return hypot(real, imaginary)
        }

        let fundamental = magnitude(at: 220)
        let secondHarmonic = magnitude(at: 440)
        let thirdHarmonic = magnitude(at: 660)
        let offHarmonicNoise = magnitude(at: 527)

        XCTAssertGreaterThan(fundamental, 1)
        XCTAssertGreaterThan(
            secondHarmonic + thirdHarmonic,
            fundamental * 0.005
        )
        XCTAssertGreaterThan(
            secondHarmonic + thirdHarmonic,
            offHarmonicNoise * 1.5
        )
    }

    func testPerformanceUsesNotationAwareLengthsAndDivisionPauses() {
        let events = [
            ChantEvent(
                id: "note-0",
                phraseID: "phrase-0",
                syllableID: "syllable-0",
                syllable: "Ky",
                relativePitch: -2,
                durationWeight: 1.5,
                modifiers: [.mora]
            ),
            ChantEvent(
                id: "note-1",
                phraseID: "phrase-0",
                syllableID: "syllable-1",
                syllable: "ri",
                relativePitch: -1,
                durationWeight: 1.25,
                modifiers: [.episema]
            ),
            ChantEvent(
                id: "note-2",
                phraseID: "phrase-0",
                syllableID: "syllable-2",
                syllable: "e",
                relativePitch: 0,
                modifiers: [.quilisma]
            ),
            ChantEvent(
                id: "note-3",
                phraseID: "phrase-1",
                syllableID: "syllable-3",
                syllable: "eléison",
                relativePitch: 1
            )
        ]
        let score = ChantScore(
            id: "rhythm",
            incipit: "Kyrie",
            gabc: "%% Ky(f.)ri(g_)e(hw) (;) eléison(i) (::)",
            reviewStatus: .humanReviewed,
            provenance: ChantProvenance(
                collection: "Test",
                sourceBook: "Test",
                license: "Test",
                snapshot: "test"
            ),
            timeline: ChantTimeline(events: events)
        )

        let performance = CantorGuideSynthesizer.performance(for: events, in: score)

        XCTAssertEqual(performance.map(\.durationWeight), [2, 1.8, 1, 1])
        XCTAssertEqual(performance.map(\.followingSilenceWeight), [0, 0, 1, 2])
        XCTAssertTrue(performance[0].startsPhrase)
        XCTAssertTrue(performance[2].endsPhrase)
        XCTAssertTrue(performance[3].startsPhrase)
        XCTAssertTrue(performance[3].endsPhrase)
    }

    func testSynthesizerKeepsAdjacentNotesAudiblyConnected() throws {
        let events = [
            ChantEvent(
                id: "note-0",
                phraseID: "phrase",
                syllableID: "syllable",
                syllable: "Ky",
                relativePitch: 0
            ),
            ChantEvent(
                id: "note-1",
                phraseID: "phrase",
                syllableID: "syllable",
                syllable: "Ky",
                relativePitch: 1
            )
        ]
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        )

        let renderer = try makeOrganRenderer(format: format)
        let first = try renderer.render(
            performanceEvent: performanceEvent(
                events[0],
                startsPhrase: true,
                startsSyllable: true,
                endsSyllable: false
            ),
            tempo: 1,
            transposition: 0,
            clef: .c3,
            register: .high
        )
        let second = try renderer.render(
            performanceEvent: performanceEvent(
                events[1],
                endsPhrase: true,
                startsSyllable: false,
                endsSyllable: true
            ),
            tempo: 1,
            transposition: 0,
            clef: .c3,
            register: .high
        )
        let firstSamples = try XCTUnwrap(first.floatChannelData?[0])
        let secondSamples = try XCTUnwrap(second.floatChannelData?[0])
        let beforePeak = ((Int(first.frameLength) - 80)..<Int(first.frameLength))
            .map { abs(firstSamples[$0]) }
            .max() ?? 0
        let afterPeak = (0..<80)
            .map { abs(secondSamples[$0]) }
            .max() ?? 0
        let boundaryDelta = abs(
            secondSamples[0] - firstSamples[Int(first.frameLength) - 1]
        )

        XCTAssertGreaterThan(beforePeak, 0.01)
        XCTAssertGreaterThan(afterPeak, 0.01)
        XCTAssertLessThan(boundaryDelta, 0.2)
    }

    func testDottedPhraseEndingDoesNotPop() throws {
        let dotted = ChantEvent(
            id: "dotted",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "convérte",
            relativePitch: 0,
            durationWeight: 2,
            modifiers: [.mora]
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        let renderer = try makeOrganRenderer(format: format)
        let buffer = try renderer.render(
            performanceEvent: CantorGuidePerformanceEvent(
                event: dotted,
                durationWeight: 2,
                followingSilenceWeight: 2,
                startsPhrase: true,
                endsPhrase: true,
                startsSyllable: true,
                endsSyllable: true
            ),
            tempo: 0.85,
            transposition: -10,
            clef: .c3,
            register: .low
        )
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let noteFrames = Int(0.38 * 2 / 0.85 * 48_000)
        var maximumDelta: Float = 0
        var maximumDeltaFrame = 0
        for frame in max(1, noteFrames - 6_000)..<Int(buffer.frameLength) {
            let delta = abs(samples[frame] - samples[frame - 1])
            if delta > maximumDelta {
                maximumDelta = delta
                maximumDeltaFrame = frame
            }
        }

        XCTAssertLessThan(
            maximumDelta,
            0.01,
            "maximumDelta=\(maximumDelta) at frame \(maximumDeltaFrame), "
                + "noteFrames=\(noteFrames)"
        )
        let silencePeak = (noteFrames..<Int(buffer.frameLength))
            .map { abs(samples[$0]) }
            .max() ?? 0
        XCTAssertEqual(samples[noteFrames - 1], 0, accuracy: 0.000_001)
        XCTAssertEqual(silencePeak, 0, accuracy: 0.000_001)
    }

    func testSalveCadenceEndsOnACleanPitchInAAndBFlat() throws {
        let relativePitches = [-4, -3, -5, -4]
        let events = relativePitches.enumerated().map { index, pitch in
            ChantEvent(
                id: "salve-\(index)",
                phraseID: "salve",
                syllableID: index < 3 ? "sal" : "ve",
                syllable: index < 3 ? "sal" : "ve",
                relativePitch: pitch,
                durationWeight: index == 3 ? 2 : 1,
                modifiers: index == 3 ? [.mora] : []
            )
        }
        let sampleRate = 48_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )

        for (name, transposition) in [("A", 0), ("B♭", 1)] {
            let renderer = try makeOrganRenderer(format: format)
            var finalBuffer: AVAudioPCMBuffer?
            for (index, event) in events.enumerated() {
                finalBuffer = try renderer.render(
                    performanceEvent: CantorGuidePerformanceEvent(
                        event: event,
                        durationWeight: event.durationWeight,
                        followingSilenceWeight: 0,
                        startsPhrase: index == 0,
                        endsPhrase: index == events.count - 1,
                        startsSyllable: index == 0 || index == 3,
                        endsSyllable: index == 2 || index == 3
                    ),
                    tempo: 0.85,
                    transposition: transposition,
                    clef: GABCClef(gabc: "(c4)"),
                    register: .low
                )
            }

            let buffer = try XCTUnwrap(finalBuffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            let start = Int(0.08 * sampleRate)
            let length = min(8_192, Int(buffer.frameLength) - start)

            func magnitude(at frequency: Double) -> Double {
                var real = 0.0
                var imaginary = 0.0
                for offset in 0..<length {
                    let window =
                        0.5
                        - 0.5
                        * cos(
                            2 * Double.pi * Double(offset)
                                / Double(length - 1)
                        )
                    let angle =
                        2 * Double.pi * frequency * Double(offset)
                        / sampleRate
                    let value = Double(samples[start + offset]) * window
                    real += value * cos(angle)
                    imaginary -= value * sin(angle)
                }
                return hypot(real, imaginary)
            }

            let target = CantorGuideSynthesizer.frequency(
                for: events[3],
                transposition: transposition,
                clef: GABCClef(gabc: "(c4)")
            )
            let priorFrequencies = [events[1], events[2]].map {
                CantorGuideSynthesizer.frequency(
                    for: $0,
                    transposition: transposition,
                    clef: GABCClef(gabc: "(c4)")
                )
            }
            let targetMagnitude = magnitude(at: target)
            let strongestPrior = priorFrequencies
                .map(magnitude(at:))
                .max() ?? 0

            XCTAssertGreaterThan(
                targetMagnitude,
                strongestPrior * 4,
                "\(name) cadence retained a prior pitch under its final note."
            )
        }
    }

    func testSynthesisStateRemainsContinuousAcrossScheduledBuffers() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        )
        let firstEvent = ChantEvent(
            id: "note-1",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0
        )
        let secondEvent = ChantEvent(
            id: "note-2",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 2
        )
        let renderer = try makeOrganRenderer(format: format)
        let first = try renderer.render(
            performanceEvent: CantorGuidePerformanceEvent(
                event: firstEvent,
                durationWeight: 1,
                followingSilenceWeight: 0,
                startsPhrase: true,
                endsPhrase: false,
                startsSyllable: true,
                endsSyllable: false
            ),
            tempo: 1,
            transposition: -10,
            clef: .c3,
            register: .low
        )
        let second = try renderer.render(
            performanceEvent: CantorGuidePerformanceEvent(
                event: secondEvent,
                durationWeight: 1,
                followingSilenceWeight: 0,
                startsPhrase: false,
                endsPhrase: false,
                startsSyllable: false,
                endsSyllable: false
            ),
            tempo: 1,
            transposition: -10,
            clef: .c3,
            register: .low
        )
        let firstSamples = try XCTUnwrap(first.floatChannelData?[0])
        let secondSamples = try XCTUnwrap(second.floatChannelData?[0])
        let boundaryDelta = abs(
            firstSamples[Int(first.frameLength) - 1] - secondSamples[0]
        )

        XCTAssertLessThan(boundaryDelta, 0.2)
    }

    #if DEBUG
    func testDebugAuditionHarnessCoversBothRegisters() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 2)
        )

        let low = try CantorGuideSynthesizer.auditionBuffers(
            register: .low,
            format: format
        )
        let high = try CantorGuideSynthesizer.auditionBuffers(
            register: .high,
            format: format
        )
        let lowFrames = low.reduce(0) { $0 + Int($1.frameLength) }
        let highFrames = high.reduce(0) { $0 + Int($1.frameLength) }

        XCTAssertEqual(low.count, 18)
        XCTAssertEqual(lowFrames, highFrames)
        XCTAssertGreaterThan(lowFrames, 30_000)
        XCTAssertNotEqual(
            low[1].floatChannelData?[0][1_000],
            high[1].floatChannelData?[0][1_000]
        )
    }
    #endif

    func testBundledOrganSoundBankIsPresentAndUsesItsOnlyPreset() throws {
        let url = try XCTUnwrap(OrganSoundBank.bundledURL)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber)

        XCTAssertEqual(OrganSoundBank.program, 0)
        XCTAssertEqual(OrganSoundBank.tuningCorrection, 2)
        XCTAssertEqual(
            OrganSoundBank.sha256,
            "5e30e974376a6693ebfd604d49cafd29825e272c73f7bec87392f33906f8f1d6"
        )
        XCTAssertGreaterThan(fileSize.intValue, 18_000_000)
    }

    private func makeOrganRenderer(
        format: AVAudioFormat
    ) throws -> SampledOrganRenderer {
        let soundBankURL = try XCTUnwrap(OrganSoundBank.bundledURL)
        return try SampledOrganRenderer(
            soundBankURL: soundBankURL,
            format: format
        )
    }

    private func performanceEvent(
        _ event: ChantEvent,
        startsPhrase: Bool = false,
        endsPhrase: Bool = false,
        startsSyllable: Bool = true,
        endsSyllable: Bool = true
    ) -> CantorGuidePerformanceEvent {
        CantorGuidePerformanceEvent(
            event: event,
            durationWeight: event.durationWeight,
            followingSilenceWeight: 0,
            startsPhrase: startsPhrase,
            endsPhrase: endsPhrase,
            startsSyllable: startsSyllable,
            endsSyllable: endsSyllable
        )
    }
}
