@preconcurrency import AVFoundation
import HoursCore
@testable import Hours
import XCTest

@MainActor
final class ChantPlaybackTests: XCTestCase {
    private static var retainedAudioControllers: [ChantPlaybackController] = []

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(
            forKey: ChantPlaybackController.guideSoundKey
        )
        defaults.removeObject(
            forKey: ChantPlaybackController.scholaPitchKey
        )
        defaults.removeObject(
            forKey: ChantPlaybackController.chantRegisterKey
        )
    }

    func testCantorGuideDefaultsToOneHundredPercentTempo() {
        let controller = ChantPlaybackController()

        XCTAssertEqual(controller.tempo, 1.0)
    }

    func testCantorGuideOptionsSurviveRelaunch() throws {
        let suiteName = "ChantPlaybackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let controller = ChantPlaybackController(
            userDefaults: defaults
        )

        controller.guideSound = .simpleTone
        controller.scholaPitch = .bFlat
        controller.chantRegister = .high

        let relaunchedController = ChantPlaybackController(
            userDefaults: defaults
        )
        XCTAssertEqual(relaunchedController.guideSound, .simpleTone)
        XCTAssertEqual(relaunchedController.scholaPitch, .bFlat)
        XCTAssertEqual(relaunchedController.chantRegister, .high)
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

    func testScholaPitchOptionsCoverGThroughC() {
        XCTAssertEqual(
            ScholaPitch.allCases.map(\.displayName),
            ["G", "A♭", "A", "B♭", "B", "C"]
        )
        XCTAssertEqual(
            ScholaPitch.allCases.map(\.semitoneOffset),
            [0, 1, 2, 3, 4, 5]
        )
    }

    func testScholaPitchesAndRegistersMapToTheirSoundingOctaves() {
        XCTAssertEqual(
            CantorGuideSound.allCases.map(\.displayName),
            ["Harp", "Organ", "Tone"]
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
            (.g, .low, 195.997_72),
            (.aFlat, .low, 207.652_35),
            (.a, .low, 220),
            (.bFlat, .low, 233.081_88),
            (.b, .low, 246.941_65),
            (.c, .low, 261.625_57),
            (.g, .high, 391.995_44),
            (.aFlat, .high, 415.304_70),
            (.a, .high, 440),
            (.bFlat, .high, 466.163_76),
            (.b, .high, 493.883_30),
            (.c, .high, 523.251_13)
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

    func testRenderedDominantsStayWithinSevenCentsOfEveryScholaSetting() throws {
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
            (.g, .low, 195.997_72),
            (.aFlat, .low, 207.652_35),
            (.a, .low, 220),
            (.bFlat, .low, 233.081_88),
            (.b, .low, 246.941_65),
            (.c, .low, 261.625_57),
            (.g, .high, 391.995_44),
            (.aFlat, .high, 415.304_70),
            (.a, .high, 440),
            (.bFlat, .high, 466.163_76),
            (.b, .high, 493.883_30),
            (.c, .high, 523.251_13)
        ]

        for (pitch, register, expectedFrequency) in expected {
            let renderer = try makeHarpRenderer(format: format)
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
            let expectedLag = sampleRate / expectedFrequency
            let minimumLag = Int(floor(expectedLag * 0.95))
            let maximumLag = Int(ceil(expectedLag * 1.05))
            let correlations = (minimumLag...maximumLag).map { lag in
                var sum = 0.0
                for offset in lag..<length {
                    sum += Double(samples[start + offset])
                        * Double(samples[start + offset - lag])
                }
                return sum / Double(length - lag)
            }
            let peakIndex = try XCTUnwrap(
                correlations.indices.max {
                    correlations[$0] < correlations[$1]
                }
            )
            let peakLag = minimumLag + peakIndex
            let interpolatedLag: Double
            if peakIndex > correlations.startIndex,
               peakIndex < correlations.index(before: correlations.endIndex) {
                let left = correlations[peakIndex - 1]
                let center = correlations[peakIndex]
                let right = correlations[peakIndex + 1]
                let denominator = left - 2 * center + right
                let offset = abs(denominator) > 0.000_001
                    ? 0.5 * (left - right) / denominator
                    : 0
                interpolatedLag = Double(peakLag) + offset
            } else {
                interpolatedLag = Double(peakLag)
            }
            let measuredFrequency = sampleRate / interpolatedLag
            let measuredCents =
                1_200 * log2(measuredFrequency / expectedFrequency)

            XCTAssertLessThan(
                abs(measuredCents),
                7,
                "\(pitch.displayName) \(register.displayName) was "
                    + "\(measuredCents) cents from its target."
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

    func testControllerStopsAndRestartsActiveAudio() async throws {
        let event = ChantEvent(
            id: "long-note",
            phraseID: "phrase-1",
            syllableID: "syllable-1",
            syllable: "Ky",
            relativePitch: 0,
            durationWeight: 20
        )
        let score = ChantScore(
            id: "restart-score",
            incipit: "Kyrie",
            gabc: "(c4) Ky(f)",
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
        controller.guideSound = .simpleTone

        controller.play(score: score)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.isPlaying)
        let initiallyRunning = await controller.audioEngineIsRunningForTesting()
        XCTAssertTrue(initiallyRunning)

        controller.stop()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(controller.isPlaying)
        let runningAfterStop = await controller.audioEngineIsRunningForTesting()
        XCTAssertFalse(runningAfterStop, "Stopped playback must not keep the audio hardware running")

        controller.play(score: score)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.isPlaying)
        let runningAfterRestart = await controller.audioEngineIsRunningForTesting()
        XCTAssertTrue(runningAfterRestart)

        controller.stop()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(controller.isPlaying)
        let runningAfterSecondStop = await controller.audioEngineIsRunningForTesting()
        XCTAssertFalse(runningAfterSecondStop)

        // Keep AVFoundation's app-lifetime graph out of this test's teardown.
        // The regression is for interactive stop/restart, not process exit.
        Self.retainedAudioControllers.append(controller)
    }

    func testPlaybackFadeSmoothsStopsAndRestartsAtEverySampleRate() throws {
        for sampleRate in [8_000.0, 44_100, 48_000] {
            let format = try XCTUnwrap(AVAudioFormat(
                standardFormatWithSampleRate: sampleRate, channels: 2
            ))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 127))
            buffer.frameLength = 127
            let channels = try XCTUnwrap(buffer.floatChannelData)
            let fade = ChantPlaybackFade(sampleRate: sampleRate)
            var previous: Float = 0
            // A DC input makes a discontinuity unambiguous, independently of
            // a particular instrument's waveform or oscillator phase.
            for audible in [true, false, true, false] {
                fade.setAudible(audible)
                XCTAssertFalse(fade.isSilent)
                for _ in 0..<Int(sampleRate * 0.04 / 127) + 2 {
                    for channel in 0..<2 {
                        for frame in 0..<127 { channels[channel][frame] = 1 }
                    }
                    fade.process(buffer.mutableAudioBufferList, frameCount: 127)
                    for frame in 0..<127 {
                        let sample = channels[0][frame]
                        XCTAssertEqual(sample, channels[1][frame])
                        XCTAssertGreaterThanOrEqual(sample, 0)
                        XCTAssertLessThanOrEqual(sample, 1)
                        XCTAssertLessThan(abs(sample - previous), Float(2 / (sampleRate * 0.02)))
                        previous = sample
                    }
                }
                XCTAssertEqual(previous, audible ? 1 : 0)
                XCTAssertEqual(fade.isSilent, !audible)
            }
        }
    }

    func testPlaybackFadeProcessesTheReverbOutput() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000, channels: 2
        ))
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let reverb = AVAudioUnitReverb()
        engine.attach(player)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 30
        engine.connect(player, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        let fade = ChantPlaybackFade(sampleRate: format.sampleRate)
        try fade.attach(to: reverb.audioUnit)
        defer {
            engine.stop()
            fade.detach(from: reverb.audioUnit)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        input.frameLength = input.frameCapacity
        let samples = try XCTUnwrap(input.floatChannelData)
        for frame in 0..<Int(input.frameLength) {
            for channel in 0..<2 {
                samples[channel][frame] = Float(sin(2 * .pi * 220 * Double(frame) / 48_000)) * 0.5
            }
        }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        try engine.start()
        player.scheduleBuffer(input)
        player.play()
        fade.setAudible(true)
        for _ in 0..<12 {
            XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        }
        let rendered = try XCTUnwrap(output.floatChannelData)
        XCTAssertGreaterThan((0..<512).map { abs(rendered[0][$0]) }.max() ?? 0, 0.1)
        fade.setAudible(false)
        for _ in 0..<4 {
            XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        }
        XCTAssertTrue(fade.isSilent)
        // The player and reverb are still producing audio, but the final
        // output must already be silent before pause/reset is allowed.
        for channel in 0..<2 {
            XCTAssertEqual((0..<512).map { abs(rendered[channel][$0]) }.max(), 0)
        }
        reverb.reset()
        reverb.wetDryMix = 0
        XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        XCTAssertEqual((0..<512).map { abs(rendered[0][$0]) }.max(), 0)
        fade.setAudible(true)
        for _ in 0..<4 {
            XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        }
        XCTAssertGreaterThan((0..<512).map { abs(rendered[0][$0]) }.max() ?? 0, 0.1)
    }

    func testPlaybackFadeGatesAFullyDryTonePath() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000, channels: 2
        ))
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let reverb = AVAudioUnitReverb()
        let gate = AVAudioUnitEQ(numberOfBands: 1)
        engine.attach(player)
        engine.attach(reverb)
        engine.attach(gate)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 0
        let band = gate.bands[0]
        band.filterType = .parametric
        band.frequency = 1_000
        band.bandwidth = 2
        band.gain = 0
        band.bypass = false
        gate.globalGain = 0
        engine.connect(player, to: reverb, format: format)
        engine.connect(reverb, to: gate, format: format)
        engine.connect(gate, to: engine.mainMixerNode, format: format)
        let fade = ChantPlaybackFade(sampleRate: format.sampleRate)
        try fade.attach(to: gate.audioUnit)
        defer {
            engine.stop()
            fade.detach(from: gate.audioUnit)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        input.frameLength = input.frameCapacity
        let samples = try XCTUnwrap(input.floatChannelData)
        for frame in 0..<Int(input.frameLength) {
            let tone = Float(sin(2 * .pi * 440 * Double(frame) / 48_000)) * 0.5
            for channel in 0..<2 {
                samples[channel][frame] = tone
            }
        }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        player.scheduleBuffer(input)
        player.play()
        fade.setAudible(true)
        for _ in 0..<12 {
            XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        }
        let rendered = try XCTUnwrap(output.floatChannelData)
        XCTAssertGreaterThan((0..<512).map { abs(rendered[0][$0]) }.max() ?? 0, 0.1)
        fade.setAudible(false)
        for _ in 0..<4 {
            XCTAssertEqual(try engine.renderOffline(512, to: output), .success)
        }
        XCTAssertTrue(fade.isSilent)
        for channel in 0..<2 {
            XCTAssertEqual((0..<512).map { abs(rendered[channel][$0]) }.max(), 0)
        }
    }

    func testPlaybackFadeForceSilentRestartsFromZero() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000, channels: 1
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        let channels = try XCTUnwrap(buffer.floatChannelData)
        let fade = ChantPlaybackFade(sampleRate: 48_000)
        fade.setAudible(true)
        for _ in 0..<20 {
            for frame in 0..<64 { channels[0][frame] = 1 }
            fade.process(buffer.mutableAudioBufferList, frameCount: 64)
        }
        XCTAssertEqual(channels[0][63], 1)
        XCTAssertFalse(fade.isSilent)

        fade.forceSilent()
        XCTAssertTrue(fade.isSilent)
        for frame in 0..<64 { channels[0][frame] = 1 }
        fade.process(buffer.mutableAudioBufferList, frameCount: 64)
        XCTAssertEqual(channels[0][0], 0)
        XCTAssertEqual(channels[0][63], 0)

        fade.setAudible(true)
        for frame in 0..<64 { channels[0][frame] = 1 }
        fade.process(buffer.mutableAudioBufferList, frameCount: 64)
        XCTAssertEqual(channels[0][0], 0)
        XCTAssertGreaterThan(channels[0][63], 0)
        XCTAssertLessThan(channels[0][63], 0.15)
    }

    func testRapidNoteSwitchingFinishesOnLatestNoteForEverySound() async throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("staff-scale"))
        let score = example.variants[0].score
        let controller = ChantPlaybackController()
        controller.prepare(score: score, pitchReference: example.pitchReference)
        defer {
            controller.stop()
            Self.retainedAudioControllers.append(controller)
        }
        for sound in CantorGuideSound.allCases {
            controller.guideSound = sound
            for note in score.timeline.events.prefix(3) {
                controller.playNote(score: score, eventID: note.id)
                try await Task.sleep(for: .milliseconds(80))
                XCTAssertNil(controller.errorMessage, sound.displayName)
                XCTAssertEqual(controller.currentEventID, note.id, sound.displayName)
            }
            for _ in 0..<150 where controller.isPlaying {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNil(controller.errorMessage, sound.displayName)
            XCTAssertFalse(controller.isPlaying, sound.displayName)
            XCTAssertNil(controller.currentEventID, sound.displayName)
        }
    }

    func testRapidNeumeTapsDoNotRestartAudioHardware() async throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("staff-scale"))
        let score = example.variants[0].score
        let controller = ChantPlaybackController()
        controller.guideSound = .simpleTone
        controller.prepare(score: score, pitchReference: example.pitchReference)
        defer {
            controller.stop()
            Self.retainedAudioControllers.append(controller)
        }

        for note in score.timeline.events.prefix(4) {
            controller.play(score: score, fromEventID: note.id)
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertNil(controller.errorMessage)
            XCTAssertTrue(controller.isPlaying)
        }

        let startCount = await controller.audioEngineStartCountForTesting()
        XCTAssertEqual(
            startCount,
            1,
            "Switching neumes must fade the current tone, not pause and restart RemoteIO."
        )
        let stillRunning = await controller.audioEngineIsRunningForTesting()
        XCTAssertTrue(stillRunning)
    }

    func testNotePreviewPlaysOnlyTappedNoteEvenWithPhraseLoopingAndOptionChanges() async throws {
        let example = try XCTUnwrap(ChantGuideDocument.load().example("staff-scale"))
        let score = example.variants[0].score
        let controller = ChantPlaybackController()
        controller.guideSound = .simpleTone
        controller.prepare(score: score, pitchReference: example.pitchReference)
        defer {
            controller.stop()
            Self.retainedAudioControllers.append(controller)
        }

        for loops in [false, true] {
            controller.loopsPhrase = loops
            // A new tap replaces ongoing playback, including a repeated tap.
            controller.play(score: score)
            let note = score.timeline.events[1]
            controller.playNote(score: score, eventID: note.id)
            controller.playNote(score: score, eventID: note.id)
            controller.chantRegister = controller.chantRegister == .low ? .high : .low
            controller.restartIfPlaying(score: score)
            XCTAssertTrue(controller.isPlaying)
            XCTAssertEqual(controller.currentEventID, note.id)
            XCTAssertEqual(controller.preparedScoreID, score.id)

            for _ in 0..<150 where controller.isPlaying {
                XCTAssertEqual(controller.currentEventID, note.id)
                try await Task.sleep(for: .milliseconds(20))
            }

            XCTAssertNil(controller.errorMessage)
            XCTAssertFalse(controller.isPlaying, "A note preview must finish without playing subsequent notes or looping")
            XCTAssertNil(controller.currentEventID)
            XCTAssertEqual(controller.loopsPhrase, loops)
        }
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

        let renderer = try makeHarpRenderer(format: format)
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

    func testSynthesizerProducesMonoCompatibleStereoOutput() throws {
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

        let renderer = try makeHarpRenderer(format: format)
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

        XCTAssertEqual(difference, 0, accuracy: 0.000_001)
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
            let renderer = try makeHarpRenderer(format: format)
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

    func testAllGuideSoundsHaveStrongSafeOutputLevels() throws {
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
        let harp = try makeHarpRenderer(format: format)
        let organ = ModeledOrganRenderer(format: format)
        let simpleTone = PitchPipeRenderer(format: format)
        let harpBuffer = try harp.render(
            performanceEvent: performanceEvent,
            tempo: 0.85,
            transposition: -10,
            clef: .c3,
            register: .low
        )
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

        let harpPeak = try peak(in: harpBuffer)
        let organPeak = try peak(in: organBuffer)
        let simpleTonePeak = try peak(in: simpleToneBuffer)
        XCTAssertGreaterThan(harpPeak, 0.12)
        XCTAssertGreaterThan(organPeak, 0.35)
        XCTAssertGreaterThan(simpleTonePeak, 0.35)
        XCTAssertLessThanOrEqual(harpPeak, 0.9)
        XCTAssertLessThan(organPeak, 0.9)
        XCTAssertLessThan(simpleTonePeak, 0.7)
    }

    func testSimpleToneStartsAndStopsWithoutADiscontinuity() throws {
        let event = ChantEvent(
            id: "tone",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0,
            durationWeight: 2
        )
        let sampleRate = 48_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let buffer = try PitchPipeRenderer(format: format).render(
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
        let frameCount = Int(buffer.frameLength)
        XCTAssertEqual(samples[0], 0)
        XCTAssertEqual(samples[frameCount - 1], 0)

        var maximumDelta: Float = 0
        for frame in 1..<frameCount {
            maximumDelta = max(maximumDelta, abs(samples[frame] - samples[frame - 1]))
        }
        XCTAssertLessThan(
            maximumDelta,
            0.03,
            "A phrase-start or phrase-end jump in the tone is heard as a click."
        )
    }

    func testHarpRetainsHarmonicsBeyondTheFundamental() throws {
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
        let renderer = try makeHarpRenderer(format: format)
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

    func testModeledOrganMatchesApprovedGeigenHarmonicProfile() throws {
        let event = ChantEvent(
            id: "organ",
            phraseID: "phrase",
            syllableID: "syllable",
            syllable: "ah",
            relativePitch: 0,
            durationWeight: 4
        )
        let sampleRate = 48_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )
        let renderer = ModeledOrganRenderer(format: format)
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
        let length = 24_000

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
        let fourthHarmonic = magnitude(at: 880)
        let offHarmonicNoise = magnitude(at: 500)

        XCTAssertGreaterThan(fundamental, 100)
        XCTAssertEqual(
            secondHarmonic / fundamental,
            0.62,
            accuracy: 0.01
        )
        XCTAssertEqual(
            thirdHarmonic / fundamental,
            0.20,
            accuracy: 0.01
        )
        XCTAssertEqual(
            fourthHarmonic / fundamental,
            0.077,
            accuracy: 0.008
        )
        XCTAssertGreaterThan(
            fundamental,
            offHarmonicNoise * 1_000,
            "The modeled organ should not contain a sampled hiss layer."
        )
        XCTAssertEqual(ModeledOrgan.reverbWetDryMix, 4)
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

        let renderer = try makeHarpRenderer(format: format)
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
        let renderer = try makeHarpRenderer(format: format)
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

        var steadyStateDelta: Float = 0
        for frame in (
            max(1, noteFrames - 12_000)..<max(2, noteFrames - 6_000)
        ) {
            steadyStateDelta = max(
                steadyStateDelta,
                abs(samples[frame] - samples[frame - 1])
            )
        }
        XCTAssertLessThan(
            maximumDelta,
            steadyStateDelta * 1.25 + 0.002,
            "maximumDelta=\(maximumDelta) at frame \(maximumDeltaFrame), "
                + "steadyStateDelta=\(steadyStateDelta), "
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
            let renderer = try makeHarpRenderer(format: format)
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
            let isolatedRenderer = try makeHarpRenderer(format: format)
            let isolatedBuffer = try isolatedRenderer.render(
                performanceEvent: CantorGuidePerformanceEvent(
                    event: events[3],
                    durationWeight: events[3].durationWeight,
                    followingSilenceWeight: 0,
                    startsPhrase: true,
                    endsPhrase: true,
                    startsSyllable: true,
                    endsSyllable: true
                ),
                tempo: 0.85,
                transposition: transposition,
                clef: GABCClef(gabc: "(c4)"),
                register: .low
            )
            let isolatedSamples = try XCTUnwrap(
                isolatedBuffer.floatChannelData?[0]
            )
            let start = Int(0.08 * sampleRate)
            let length = min(8_192, Int(buffer.frameLength) - start)
            var referenceEnergy = 0.0
            var differenceEnergy = 0.0
            for offset in 0..<length {
                let reference = Double(isolatedSamples[start + offset])
                let difference =
                    Double(samples[start + offset]) - reference
                referenceEnergy += reference * reference
                differenceEnergy += difference * difference
            }
            XCTAssertLessThan(
                sqrt(differenceEnergy / Double(length)),
                sqrt(referenceEnergy / Double(length)) * 0.05,
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
        let renderer = try makeHarpRenderer(format: format)
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

    func testBundledHarpSoundBankIsPresentAndUsesItsOnlyPreset() throws {
        let url = try XCTUnwrap(HarpSoundBank.bundledURL)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber)

        XCTAssertEqual(HarpSoundBank.program, 0)
        XCTAssertEqual(HarpSoundBank.tuningCorrection, 7)
        XCTAssertEqual(HarpSoundBank.reverbWetDryMix, 10)
        XCTAssertEqual(
            HarpSoundBank.sha256,
            "ac8aeee47a423c3cfaa3ccc17cca2eef1ca0dc86a7c3a1cfd4334f1afe4c4c37"
        )
        XCTAssertGreaterThan(fileSize.intValue, 17_000_000)
    }

    private func makeHarpRenderer(
        format: AVAudioFormat
    ) throws -> SampledHarpRenderer {
        let soundBankURL = try XCTUnwrap(HarpSoundBank.bundledURL)
        return try SampledHarpRenderer(
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
