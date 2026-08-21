@preconcurrency import AVFoundation
import Foundation
import HoursCore
import Observation

nonisolated enum ScholaPitch: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case g = 0
    case aFlat = 1
    case a = 2
    case bFlat = 3
    case b = 4
    case c = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .g: "G"
        case .aFlat: "A♭"
        case .a: "A"
        case .bFlat: "B♭"
        case .b: "B"
        case .c: "C"
        }
    }

    var semitoneOffset: Int { rawValue }
}

nonisolated enum ChantRegister: Int, CaseIterable, Identifiable, Sendable, Hashable {
    case low
    case high

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .high: "High"
        }
    }

    var octaveOffset: Int {
        switch self {
        case .low: -12
        case .high: 0
        }
    }
}

nonisolated enum CantorGuideSound: String, CaseIterable, Identifiable, Sendable, Hashable {
    case harp
    case organ
    case simpleTone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .harp: "Harp"
        case .organ: "Organ"
        case .simpleTone: "Tone"
        }
    }
}

@MainActor
@Observable
final class ChantPlaybackController {
    static let defaultTempo = 1.0
    nonisolated static let scholaPitchKey = "cantorGuide.scholaPitch"
    nonisolated static let chantRegisterKey = "cantorGuide.register"
    nonisolated static let guideSoundKey = "cantorGuide.sound"

    private(set) var isPlaying = false
    private(set) var currentEventID: String?
    private(set) var preparedScoreID: String?
    private(set) var errorMessage: String?

    var tempo = ChantPlaybackController.defaultTempo
    var scholaPitch: ScholaPitch = .a {
        didSet {
            guard scholaPitch != oldValue else { return }
            userDefaults.set(
                scholaPitch.rawValue,
                forKey: Self.scholaPitchKey
            )
            restartAfterGuideSelectionChange()
        }
    }
    var chantRegister: ChantRegister = .low {
        didSet {
            guard chantRegister != oldValue else { return }
            userDefaults.set(
                chantRegister.rawValue,
                forKey: Self.chantRegisterKey
            )
            restartAfterGuideSelectionChange()
        }
    }
    var guideSound: CantorGuideSound = .organ {
        didSet {
            guard guideSound != oldValue else { return }
            userDefaults.set(
                guideSound.rawValue,
                forKey: Self.guideSoundKey
            )
            restartAfterGuideSelectionChange()
        }
    }
    var loopsPhrase = false

    var targetDominantOffset: Int {
        scholaPitch.semitoneOffset + chantRegister.octaveOffset
    }

    private let audioPlayer = ChantAudioPlayer()
    private let lifecycleObservers = AudioLifecycleObserverBag()
    @ObservationIgnored
    private let userDefaults: UserDefaults
    private var activeScore: ChantScore?
    private var activeStartEventID: String?
    private var playbackID: UUID?

    private static let scheduledBufferWindow = 8

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let rawSound = userDefaults.string(
            forKey: Self.guideSoundKey
        ), let savedSound = CantorGuideSound(rawValue: rawSound) {
            guideSound = savedSound
        }
        if userDefaults.object(forKey: Self.scholaPitchKey) != nil,
           let savedPitch = ScholaPitch(
               rawValue: userDefaults.integer(
                   forKey: Self.scholaPitchKey
               )
           ) {
            scholaPitch = savedPitch
        }
        if userDefaults.object(forKey: Self.chantRegisterKey) != nil,
           let savedRegister = ChantRegister(
               rawValue: userDefaults.integer(
                   forKey: Self.chantRegisterKey
               )
           ) {
            chantRegister = savedRegister
        }
        observeAudioLifecycle()
    }

    func prepare(score: ChantScore) {
        if preparedScoreID != score.id {
            stop()
        }
        activeScore = score
        preparedScoreID = score.id
    }

    func toggle(score: ChantScore) {
        if isPlaying, preparedScoreID == score.id {
            stop()
        } else {
            play(score: score, fromEventID: activeStartEventID)
        }
    }

    func play(score: ChantScore, fromEventID: String? = nil) {
        playbackID = nil
        isPlaying = false
        currentEventID = nil
        audioPlayer.stop()
        activeScore = score
        preparedScoreID = score.id
        activeStartEventID = fromEventID

        let selectedEvents = selectedEvents(in: score, fromEventID: fromEventID)
        let timeline = CantorGuideSynthesizer.performance(
            for: selectedEvents,
            in: score
        )
        guard !timeline.isEmpty else {
            errorMessage = "This chant has no playable notes."
            return
        }

        isPlaying = true
        errorMessage = nil
        let tempoAtStart = tempo
        let clefAtStart = GABCClef(gabc: score.gabc)
        let transpositionAtStart = CantorGuideSynthesizer.centeredTransposition(
            for: score.timeline.events,
            targetOffset: targetDominantOffset,
            clef: clefAtStart
        )
        let registerAtStart = chantRegister
        let soundAtStart = guideSound
        let loopsAtStart = loopsPhrase
        let playbackID = UUID()
        self.playbackID = playbackID

        let initialBufferCount = loopsAtStart
            ? Self.scheduledBufferWindow
            : min(Self.scheduledBufferWindow, timeline.count)
        let initialEvents = (0..<initialBufferCount).compactMap {
            event(at: $0, in: timeline, loops: loopsAtStart)
        }
        currentEventID = timeline[0].event.id
        Task {
            guard self.playbackID == playbackID else { return }
            do {
                try await audioPlayer.start(
                    events: initialEvents,
                    tempo: tempoAtStart,
                    transposition: transpositionAtStart,
                    clef: clefAtStart,
                    register: registerAtStart,
                    sound: soundAtStart,
                    completion: initialEventCompletion(
                        timeline: timeline,
                        loops: loopsAtStart,
                        playbackID: playbackID,
                        tempo: tempoAtStart,
                        transposition: transpositionAtStart,
                        clef: clefAtStart,
                        register: registerAtStart
                    )
                )
            } catch {
                guard self.playbackID == playbackID else { return }
                self.playbackID = nil
                self.isPlaying = false
                self.currentEventID = nil
                self.errorMessage = "Couldn’t start audio output. \(error.localizedDescription)"
            }
        }
    }

    func restartIfPlaying(score: ChantScore) {
        guard isPlaying else { return }
        play(score: score, fromEventID: activeStartEventID)
    }

    private func restartAfterGuideSelectionChange() {
        guard isPlaying, let activeScore else { return }
        play(score: activeScore, fromEventID: activeStartEventID)
    }

    #if DEBUG
    func simulateViewportFollow(
        score: ChantScore,
        fromEventID: String?
    ) {
        stop()
        prepare(score: score)
        activeStartEventID = fromEventID

        let events = score.timeline.events
        let startIndex = fromEventID.flatMap { eventID in
            events.firstIndex(where: { $0.id == eventID })
        } ?? 0
        guard events.indices.contains(startIndex) else { return }

        let playbackID = UUID()
        self.playbackID = playbackID
        isPlaying = true
        errorMessage = nil
        currentEventID = events[startIndex].id

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self,
                  self.playbackID == playbackID else {
                return
            }
            let followedIndex = min(startIndex + 180, events.count - 1)
            self.currentEventID = events[followedIndex].id
        }
    }
    #endif

    func stop() {
        playbackID = nil
        isPlaying = false
        currentEventID = nil
        audioPlayer.stop()
    }

    private func selectedEvents(in score: ChantScore, fromEventID: String?) -> [ChantEvent] {
        let events = score.timeline.events
        let startIndex = fromEventID.flatMap { id in events.firstIndex(where: { $0.id == id }) } ?? 0
        guard events.indices.contains(startIndex) else { return [] }
        let remaining = Array(events[startIndex...])
        guard loopsPhrase, let phraseID = remaining.first?.phraseID else { return remaining }
        return remaining.prefix { $0.phraseID == phraseID }.map(\.self)
    }

    private func schedule(
        position: Int,
        timeline: [CantorGuidePerformanceEvent],
        loops: Bool,
        playbackID: UUID,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister
    ) {
        guard let event = event(at: position, in: timeline, loops: loops) else {
            return
        }

        audioPlayer.schedule(
            event: event,
            tempo: tempo,
            transposition: transposition,
            clef: clef,
            register: register,
            completion: eventCompletion(
                position: position,
                timeline: timeline,
                loops: loops,
                playbackID: playbackID,
                tempo: tempo,
                transposition: transposition,
                clef: clef,
                register: register
            )
        )
    }

    private func initialEventCompletion(
        timeline: [CantorGuidePerformanceEvent],
        loops: Bool,
        playbackID: UUID,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister
    ) -> @Sendable (Int) -> Void {
        { [weak self] position in
            Task { @MainActor in
                self?.didFinishEvent(
                    at: position,
                    timeline: timeline,
                    loops: loops,
                    playbackID: playbackID,
                    tempo: tempo,
                    transposition: transposition,
                    clef: clef,
                    register: register
                )
            }
        }
    }

    private func eventCompletion(
        position: Int,
        timeline: [CantorGuidePerformanceEvent],
        loops: Bool,
        playbackID: UUID,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister
    ) -> @Sendable () -> Void {
        { [weak self] in
            Task { @MainActor in
                self?.didFinishEvent(
                    at: position,
                    timeline: timeline,
                    loops: loops,
                    playbackID: playbackID,
                    tempo: tempo,
                    transposition: transposition,
                    clef: clef,
                    register: register
                )
            }
        }
    }

    private func didFinishEvent(
        at position: Int,
        timeline: [CantorGuidePerformanceEvent],
        loops: Bool,
        playbackID: UUID,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister
    ) {
        guard self.playbackID == playbackID else { return }

        let nextPosition = position + 1
        guard let nextEvent = event(
            at: nextPosition,
            in: timeline,
            loops: loops
        ) else {
            stop()
            return
        }

        currentEventID = nextEvent.event.id
        schedule(
            position: position + Self.scheduledBufferWindow,
            timeline: timeline,
            loops: loops,
            playbackID: playbackID,
            tempo: tempo,
            transposition: transposition,
            clef: clef,
            register: register
        )
    }

    private func event(
        at position: Int,
        in timeline: [CantorGuidePerformanceEvent],
        loops: Bool
    ) -> CantorGuidePerformanceEvent? {
        guard position >= 0, !timeline.isEmpty else { return nil }
        if loops {
            return timeline[position % timeline.count]
        }
        guard timeline.indices.contains(position) else { return nil }
        return timeline[position]
    }

    private func invalidateEngineConfiguration() {
        playbackID = nil
        isPlaying = false
        currentEventID = nil
        audioPlayer.invalidate()
    }

    private func observeAudioLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.tokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard let typeValue,
                      AVAudioSession.InterruptionType(rawValue: typeValue) == .began else { return }
                Task { @MainActor in
                    self?.invalidateEngineConfiguration()
                }
            }
        )
        lifecycleObservers.tokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard let reasonValue,
                      AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable else {
                    return
                }
                Task { @MainActor in
                    self?.invalidateEngineConfiguration()
                }
            }
        )
        lifecycleObservers.tokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.invalidateEngineConfiguration()
                }
            }
        )
    }
}

private nonisolated final class ChantAudioPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.matthewmccarty.hours.chant-audio",
        qos: .default
    )
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let guideReverb = AVAudioUnitReverb()
    private var format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 1
    )!
    private var isEngineConfigured = false
    private var harpRenderer: SampledHarpRenderer?
    private var organRenderer: ModeledOrganRenderer?
    private var pitchPipeRenderer: PitchPipeRenderer?

    init() {
        engine.attach(player)
        engine.attach(guideReverb)
        guideReverb.loadFactoryPreset(.mediumRoom)
        guideReverb.wetDryMix = 0
    }

    func start(
        events: [CantorGuidePerformanceEvent],
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister,
        sound: CantorGuideSound,
        completion: @escaping @Sendable (Int) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(qos: .default, flags: .enforceQoS) { [self] in
                do {
                    try activateAudioSession()
                    try configureEngineIfNeeded()
                    if !engine.isRunning {
                        try engine.start()
                    }
                    harpRenderer = nil
                    organRenderer = nil
                    pitchPipeRenderer = nil
                    guideReverb.reset()
                    switch sound {
                    case .harp:
                        guard let soundBankURL = HarpSoundBank.bundledURL else {
                            throw CantorGuideAudioError.soundBankUnavailable
                        }
                        guideReverb.wetDryMix = HarpSoundBank.reverbWetDryMix
                        harpRenderer = try SampledHarpRenderer(
                            soundBankURL: soundBankURL,
                            format: format
                        )
                    case .organ:
                        guideReverb.wetDryMix =
                            ModeledOrgan.reverbWetDryMix
                        organRenderer = ModeledOrganRenderer(format: format)
                    case .simpleTone:
                        guideReverb.wetDryMix = 0
                        pitchPipeRenderer = PitchPipeRenderer(format: format)
                    }
                    for (position, event) in events.enumerated() {
                        try scheduleImmediately(
                            event: event,
                            tempo: tempo,
                            transposition: transposition,
                            clef: clef,
                            register: register,
                            options: position == events.startIndex
                                ? .interrupts
                                : []
                        ) {
                            completion(position)
                        }
                    }
                    player.play()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func schedule(
        event: CantorGuidePerformanceEvent,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister,
        completion: @escaping @Sendable () -> Void
    ) {
        queue.async(qos: .default, flags: .enforceQoS) { [self] in
            do {
                try scheduleImmediately(
                    event: event,
                    tempo: tempo,
                    transposition: transposition,
                    clef: clef,
                    register: register,
                    completion: completion
                )
            } catch {
                completion()
            }
        }
    }

    func stop() {
        queue.async(qos: .default, flags: .enforceQoS) { [self] in
            // AVAudioPlayerNode.stop() synchronously unschedules buffers and
            // can invert priority with its user-interactive render thread.
            // The next start interrupts this paused buffer queue instead.
            player.pause()
            harpRenderer = nil
            organRenderer = nil
            pitchPipeRenderer = nil
        }
    }

    func invalidate() {
        queue.async(qos: .default, flags: .enforceQoS) { [self] in
            player.pause()
            harpRenderer = nil
            organRenderer = nil
            pitchPipeRenderer = nil
            engine.stop()
            if isEngineConfigured {
                engine.disconnectNodeOutput(player)
                engine.disconnectNodeOutput(guideReverb)
            }
            engine.reset()
            isEngineConfigured = false
        }
    }

    private func scheduleImmediately(
        event: CantorGuidePerformanceEvent,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register: ChantRegister,
        options: AVAudioPlayerNodeBufferOptions = [],
        completion: @escaping @Sendable () -> Void
    ) throws {
        let buffer: AVAudioPCMBuffer
        if let harpRenderer {
            buffer = try harpRenderer.render(
                performanceEvent: event,
                tempo: tempo,
                transposition: transposition,
                clef: clef,
                register: register
            )
        } else if let organRenderer {
            buffer = try organRenderer.render(
                performanceEvent: event,
                tempo: tempo,
                transposition: transposition,
                clef: clef,
                register: register
            )
        } else if let pitchPipeRenderer {
            buffer = try pitchPipeRenderer.render(
                performanceEvent: event,
                tempo: tempo,
                transposition: transposition,
                clef: clef,
                register: register
            )
        } else {
            throw CantorGuideAudioError.outputUnavailable
        }
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: options,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            completion()
        }
    }

    private func configureEngineIfNeeded() throws {
        guard !isEngineConfigured else { return }

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        guard outputFormat.sampleRate > 0,
              outputFormat.channelCount > 0,
              let deviceFormat = AVAudioFormat(
                standardFormatWithSampleRate: outputFormat.sampleRate,
                channels: outputFormat.channelCount
              ) else {
            throw CantorGuideAudioError.outputUnavailable
        }

        format = deviceFormat
        engine.connect(player, to: guideReverb, format: format)
        engine.connect(guideReverb, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isEngineConfigured = true
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
}

private nonisolated enum CantorGuideAudioError: LocalizedError {
    case outputUnavailable
    case soundBankUnavailable

    var errorDescription: String? {
        switch self {
        case .outputUnavailable:
            "No audio output is currently available."
        case .soundBankUnavailable:
            "The harp sound bank could not be loaded."
        }
    }
}

private final class AudioLifecycleObserverBag: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}

nonisolated struct CantorGuidePerformanceEvent: Sendable {
    let event: ChantEvent
    let durationWeight: Double
    let followingSilenceWeight: Double
    let startsPhrase: Bool
    let endsPhrase: Bool
    let startsSyllable: Bool
    let endsSyllable: Bool
}

nonisolated enum HarpSoundBank {
    static let resourceName = "ConcertHarp"
    static let program: UInt8 = 0
    static let tuningCorrection: Float = 7
    static let reverbWetDryMix: Float = 10
    static let sha256 =
        "ac8aeee47a423c3cfaa3ccc17cca2eef1ca0dc86a7c3a1cfd4334f1afe4c4c37"

    static var bundledURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "sf2")
    }
}

nonisolated enum ModeledOrgan {
    static let reverbWetDryMix: Float = 4
    static let harmonicAmplitudes = [
        1.0,
        0.62,
        0.20,
        0.077,
        0.019,
        0.016,
        0.024,
        0.006,
        0.001
    ]
}

nonisolated final class SampledHarpRenderer: @unchecked Sendable {
    private static let secondsPerBeat = 0.38
    private static let transitionSeconds = 0.018
    private static let phraseAttackSeconds = 0.006
    private static let phraseReleaseSeconds = 0.08
    private static let syllablePulseSeconds = 0.006
    private static let outputGain = 2.4
    private static let peakLimit: Float = 0.9

    private let engine = AVAudioEngine()
    private let samplers: [AVAudioUnitSampler]
    private let voiceMixers: [AVAudioMixerNode]
    private let format: AVAudioFormat
    private let scratchBuffer: AVAudioPCMBuffer
    private var currentVoiceIndex: Int?

    init(soundBankURL: URL, format: AVAudioFormat) throws {
        self.format = format
        samplers = [AVAudioUnitSampler(), AVAudioUnitSampler()]
        voiceMixers = [AVAudioMixerNode(), AVAudioMixerNode()]
        for index in samplers.indices {
            let sampler = samplers[index]
            let mixer = voiceMixers[index]
            engine.attach(sampler)
            engine.attach(mixer)
            engine.connect(sampler, to: mixer, format: nil)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            try sampler.loadSoundBankInstrument(
                at: soundBankURL,
                program: HarpSoundBank.program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            sampler.globalTuning = HarpSoundBank.tuningCorrection
            mixer.outputVolume = 0
        }
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 4_096
        )
        guard let scratchBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw SampledHarpRenderingError.bufferUnavailable
        }
        self.scratchBuffer = scratchBuffer
        try engine.start()
    }

    deinit {
        silenceAllVoices()
        engine.stop()
    }

    func render(
        performanceEvent: CantorGuidePerformanceEvent,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register _: ChantRegister
    ) throws -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let safeTempo = max(0.1, tempo)
        let noteSeconds = max(
            0.09,
            Self.secondsPerBeat * performanceEvent.durationWeight / safeTempo
        )
        let silenceSeconds =
            Self.secondsPerBeat
            * performanceEvent.followingSilenceWeight
            / safeTempo
        let noteFrames = max(1, Int(noteSeconds * sampleRate))
        let silenceFrames = max(0, Int(silenceSeconds * sampleRate))
        let totalFrames = max(1, noteFrames + silenceFrames)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw SampledHarpRenderingError.bufferUnavailable
        }
        output.frameLength = AVAudioFrameCount(totalFrames)
        clear(output)

        if performanceEvent.startsPhrase {
            silenceAllVoices()
        }

        let semitoneOffset = CantorGuideSynthesizer.semitoneOffset(
            for: performanceEvent.event,
            clef: clef
        )
        let midiValue = min(127, max(0, 67 + semitoneOffset + transposition))
        let midiNote = UInt8(midiValue)
        var writeOffset = 0

        let oldVoiceIndex = currentVoiceIndex
        let newVoiceIndex = oldVoiceIndex.map { 1 - $0 } ?? 0
        prepareVoice(newVoiceIndex, for: midiNote)
        currentVoiceIndex = newVoiceIndex

        if let oldVoiceIndex {
            let transitionFrames = min(
                noteFrames,
                max(1, Int(Self.transitionSeconds * sampleRate))
            )
            try renderCrossfade(
                transitionFrames,
                from: oldVoiceIndex,
                to: newVoiceIndex,
                into: output
            )
            silenceVoice(oldVoiceIndex)
            voiceMixers[newVoiceIndex].outputVolume = 1
            writeOffset = transitionFrames
        } else {
            voiceMixers[newVoiceIndex].outputVolume = 1
        }

        try renderFrames(
            noteFrames - writeOffset,
            into: output,
            at: writeOffset
        )
        writeOffset = noteFrames

        let shouldRelease = performanceEvent.endsPhrase || silenceFrames > 0
        if shouldRelease, let currentVoiceIndex {
            silenceVoice(currentVoiceIndex)
            self.currentVoiceIndex = nil
        }
        try renderFrames(
            totalFrames - writeOffset,
            into: output,
            at: writeOffset
        )

        applyArticulationEnvelope(
            to: output,
            noteFrames: noteFrames,
            performanceEvent: performanceEvent,
            shouldRelease: shouldRelease
        )
        return output
    }

    private func prepareVoice(_ index: Int, for midiNote: UInt8) {
        silenceVoice(index)
        samplers[index].startNote(
            midiNote,
            withVelocity: 58,
            onChannel: 0
        )
    }

    private func silenceVoice(_ index: Int) {
        voiceMixers[index].outputVolume = 0
        samplers[index].sendController(120, withValue: 0, onChannel: 0)
    }

    private func silenceAllVoices() {
        for index in samplers.indices {
            silenceVoice(index)
        }
        currentVoiceIndex = nil
    }

    private func renderCrossfade(
        _ requestedFrames: Int,
        from oldVoiceIndex: Int,
        to newVoiceIndex: Int,
        into output: AVAudioPCMBuffer
    ) throws {
        guard requestedFrames > 0 else { return }
        let rampStepFrames = max(
            1,
            min(
                requestedFrames,
                Int(format.sampleRate * 0.001)
            )
        )
        var writeOffset = 0
        while writeOffset < requestedFrames {
            let frameCount = min(
                rampStepFrames,
                requestedFrames - writeOffset
            )
            let midpoint = Double(writeOffset) + Double(frameCount) * 0.5
            let progress = min(1, midpoint / Double(requestedFrames))
            voiceMixers[oldVoiceIndex].outputVolume = Float(
                cos(progress * .pi * 0.5)
            )
            voiceMixers[newVoiceIndex].outputVolume = Float(
                sin(progress * .pi * 0.5)
            )
            try renderFrames(
                frameCount,
                into: output,
                at: writeOffset
            )
            writeOffset += frameCount
        }
    }

    private func clear(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                channels[channel][frame] = 0
            }
        }
    }

    private func renderFrames(
        _ requestedFrames: Int,
        into output: AVAudioPCMBuffer,
        at outputOffset: Int
    ) throws {
        guard requestedFrames > 0,
              let outputChannels = output.floatChannelData else {
            return
        }

        var remaining = requestedFrames
        var writeOffset = outputOffset
        var retryCount = 0
        while remaining > 0 {
            let frameCount = min(
                AVAudioFrameCount(remaining),
                engine.manualRenderingMaximumFrameCount
            )
            let status = try engine.renderOffline(frameCount, to: scratchBuffer)
            switch status {
            case .success:
                guard let scratchChannels = scratchBuffer.floatChannelData else {
                    throw SampledHarpRenderingError.bufferUnavailable
                }
                let renderedFrames = Int(scratchBuffer.frameLength)
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<renderedFrames {
                        outputChannels[channel][writeOffset + frame] =
                            scratchChannels[channel][frame]
                    }
                }
                remaining -= renderedFrames
                writeOffset += renderedFrames
                retryCount = 0
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                retryCount += 1
                if retryCount > 16 {
                    throw SampledHarpRenderingError.renderStalled
                }
            case .error:
                throw SampledHarpRenderingError.renderFailed
            @unknown default:
                throw SampledHarpRenderingError.renderFailed
            }
        }
    }

    private func applyArticulationEnvelope(
        to buffer: AVAudioPCMBuffer,
        noteFrames: Int,
        performanceEvent: CantorGuidePerformanceEvent,
        shouldRelease: Bool
    ) {
        guard let channels = buffer.floatChannelData else { return }
        let sampleRate = format.sampleRate
        let startLevel = performanceEvent.startsPhrase
            ? 0.0
            : performanceEvent.startsSyllable ? 0.88 : 1.0
        let endLevel = shouldRelease
            ? 0.0
            : performanceEvent.endsSyllable ? 0.88 : 1.0
        let attackSeconds = startLevel == 0
            ? Self.phraseAttackSeconds
            : Self.syllablePulseSeconds
        let releaseSeconds = endLevel == 0
            ? Self.phraseReleaseSeconds
            : Self.syllablePulseSeconds
        let attackFrames = max(
            1,
            min(noteFrames / 3, Int(attackSeconds * sampleRate))
        )
        let releaseFrames = max(
            1,
            min(noteFrames / 3, Int(releaseSeconds * sampleRate))
        )

        for frame in 0..<Int(buffer.frameLength) {
            let envelope: Double
            if frame < noteFrames {
                let attackProgress = min(
                    1.0,
                    Double(frame) / Double(attackFrames)
                )
                let releaseProgress = min(
                    1.0,
                    Double(noteFrames - frame - 1) / Double(releaseFrames)
                )
                let attack = Self.smoothTransition(
                    from: startLevel,
                    to: 1,
                    progress: attackProgress
                )
                let release = Self.smoothTransition(
                    from: endLevel,
                    to: 1,
                    progress: releaseProgress
                )
                envelope = min(attack, release)
            } else {
                envelope = 0
            }
            let gain = Float(envelope * Self.outputGain)
            for channel in 0..<Int(buffer.format.channelCount) {
                channels[channel][frame] *= gain
            }
        }
        limitPeak(in: buffer)
    }

    private func limitPeak(in buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame]))
            }
        }
        guard peak > Self.peakLimit else { return }
        let gain = Self.peakLimit / peak
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                channels[channel][frame] *= gain
            }
        }
    }

    private static func smoothTransition(
        from start: Double,
        to end: Double,
        progress: Double
    ) -> Double {
        let clamped = min(1, max(0, progress))
        let eased = 0.5 - 0.5 * cos(.pi * clamped)
        return start + (end - start) * eased
    }
}

nonisolated final class ModeledOrganRenderer: @unchecked Sendable {
    private static let secondsPerBeat = 0.38
    private static let attackSeconds = 0.022
    private static let releaseSeconds = 0.085
    private static let harmonicPhaseOffset = 0.417
    private static let outputGain = 0.575_8

    private let format: AVAudioFormat

    init(format: AVAudioFormat) {
        self.format = format
    }

    func render(
        performanceEvent: CantorGuidePerformanceEvent,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register _: ChantRegister
    ) throws -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let safeTempo = max(0.1, tempo)
        let noteSeconds = max(
            0.09,
            Self.secondsPerBeat * performanceEvent.durationWeight / safeTempo
        )
        let silenceSeconds =
            Self.secondsPerBeat
            * performanceEvent.followingSilenceWeight
            / safeTempo
        let noteFrames = max(1, Int(noteSeconds * sampleRate))
        let silenceFrames = max(0, Int(silenceSeconds * sampleRate))
        let totalFrames = max(1, noteFrames + silenceFrames)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw ModeledOrganRenderingError.bufferUnavailable
        }
        output.frameLength = AVAudioFrameCount(totalFrames)
        guard let channels = output.floatChannelData else {
            throw ModeledOrganRenderingError.bufferUnavailable
        }

        let frequency = CantorGuideSynthesizer.frequency(
            for: performanceEvent.event,
            transposition: transposition,
            clef: clef
        )
        let attackFrames = max(
            1,
            min(noteFrames, Int(Self.attackSeconds * sampleRate))
        )
        let releaseFrames = max(
            1,
            min(noteFrames, Int(Self.releaseSeconds * sampleRate))
        )

        for frame in 0..<noteFrames {
            let time = Double(frame) / sampleRate
            var tone = 0.0
            for (index, amplitude) in ModeledOrgan
                .harmonicAmplitudes.enumerated() {
                let harmonic = index + 1
                let harmonicFrequency = Double(harmonic) * frequency
                guard harmonicFrequency < sampleRate * 0.45 else {
                    continue
                }
                let phase =
                    2 * Double.pi * harmonicFrequency * time
                    + Double(harmonic) * Self.harmonicPhaseOffset
                tone += amplitude * sin(phase)
            }

            let attackProgress = min(
                1.0,
                Double(frame) / Double(attackFrames)
            )
            let releaseProgress = min(
                1.0,
                Double(noteFrames - frame - 1) / Double(releaseFrames)
            )
            let attack = 0.5 - 0.5 * cos(.pi * attackProgress)
            let release = 0.5 - 0.5 * cos(.pi * releaseProgress)
            let sample = Float(
                tone * min(attack, release) * Self.outputGain
            )
            for channel in 0..<Int(output.format.channelCount) {
                let perspective: Float =
                    output.format.channelCount > 1 && channel == 0
                    ? 0.995
                    : 1
                channels[channel][frame] = sample * perspective
            }
        }
        for frame in noteFrames..<totalFrames {
            for channel in 0..<Int(output.format.channelCount) {
                channels[channel][frame] = 0
            }
        }
        return output
    }
}

nonisolated final class PitchPipeRenderer: @unchecked Sendable {
    private static let secondsPerBeat = 0.38
    private static let transitionSeconds = 0.018
    private static let phraseAttackSeconds = 0.045
    private static let phraseReleaseSeconds = 0.08
    private static let syllablePulseSeconds = 0.018
    private static let harmonicAmplitudes = [1.0, 0.22, 0.10, 0.045, 0.02]
    private static let harmonicAmplitudeTotal =
        harmonicAmplitudes.reduce(0, +)
    private static let outputGain = 0.62 / harmonicAmplitudeTotal

    private let format: AVAudioFormat
    private var phase = 0.0
    private var previousFrequency: Double?

    init(format: AVAudioFormat) {
        self.format = format
    }

    func render(
        performanceEvent: CantorGuidePerformanceEvent,
        tempo: Double,
        transposition: Int,
        clef: GABCClef,
        register _: ChantRegister
    ) throws -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let safeTempo = max(0.1, tempo)
        let noteSeconds = max(
            0.09,
            Self.secondsPerBeat * performanceEvent.durationWeight / safeTempo
        )
        let silenceSeconds =
            Self.secondsPerBeat
            * performanceEvent.followingSilenceWeight
            / safeTempo
        let noteFrames = max(1, Int(noteSeconds * sampleRate))
        let silenceFrames = max(0, Int(silenceSeconds * sampleRate))
        let totalFrames = max(1, noteFrames + silenceFrames)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw PitchPipeRenderingError.bufferUnavailable
        }
        output.frameLength = AVAudioFrameCount(totalFrames)
        guard let channels = output.floatChannelData else {
            throw PitchPipeRenderingError.bufferUnavailable
        }

        if performanceEvent.startsPhrase {
            phase = 0
            previousFrequency = nil
        }
        let targetFrequency = CantorGuideSynthesizer.frequency(
            for: performanceEvent.event,
            transposition: transposition,
            clef: clef
        )
        let startingFrequency = previousFrequency ?? targetFrequency
        let transitionFrames = startingFrequency == targetFrequency
            ? 0
            : min(
                noteFrames,
                max(1, Int(Self.transitionSeconds * sampleRate))
            )
        let shouldRelease = performanceEvent.endsPhrase || silenceFrames > 0
        let startLevel = performanceEvent.startsPhrase
            ? 0.0
            : performanceEvent.startsSyllable ? 0.88 : 1.0
        let endLevel = shouldRelease
            ? 0.0
            : performanceEvent.endsSyllable ? 0.88 : 1.0
        let attackSeconds = startLevel == 0
            ? Self.phraseAttackSeconds
            : Self.syllablePulseSeconds
        let releaseSeconds = endLevel == 0
            ? Self.phraseReleaseSeconds
            : Self.syllablePulseSeconds
        let attackFrames = max(
            1,
            min(noteFrames / 3, Int(attackSeconds * sampleRate))
        )
        let releaseFrames = max(
            1,
            min(noteFrames / 3, Int(releaseSeconds * sampleRate))
        )

        for frame in 0..<noteFrames {
            let transitionProgress = transitionFrames == 0
                ? 1.0
                : min(1.0, Double(frame) / Double(transitionFrames))
            let frequency = Self.smoothTransition(
                from: startingFrequency,
                to: targetFrequency,
                progress: transitionProgress
            )
            phase += 2 * Double.pi * frequency / sampleRate
            if phase >= 2 * Double.pi {
                phase.formTruncatingRemainder(dividingBy: 2 * Double.pi)
            }

            var tone = 0.0
            for (index, amplitude) in Self.harmonicAmplitudes.enumerated() {
                let harmonic = index + 1
                guard Double(harmonic) * frequency < sampleRate * 0.48 else {
                    continue
                }
                tone += amplitude * sin(Double(harmonic) * phase)
            }

            let attackProgress = min(
                1.0,
                Double(frame) / Double(attackFrames)
            )
            let releaseProgress = min(
                1.0,
                Double(noteFrames - frame - 1) / Double(releaseFrames)
            )
            let attack = Self.smoothTransition(
                from: startLevel,
                to: 1,
                progress: attackProgress
            )
            let release = Self.smoothTransition(
                from: endLevel,
                to: 1,
                progress: releaseProgress
            )
            let sample = Float(
                tone * min(attack, release) * Self.outputGain
            )
            for channel in 0..<Int(output.format.channelCount) {
                channels[channel][frame] = sample
            }
        }
        for frame in noteFrames..<totalFrames {
            for channel in 0..<Int(output.format.channelCount) {
                channels[channel][frame] = 0
            }
        }

        previousFrequency = shouldRelease ? nil : targetFrequency
        return output
    }

    private static func smoothTransition(
        from start: Double,
        to end: Double,
        progress: Double
    ) -> Double {
        let clamped = min(1, max(0, progress))
        let eased = 0.5 - 0.5 * cos(.pi * clamped)
        return start + (end - start) * eased
    }
}

private nonisolated enum SampledHarpRenderingError: Error {
    case bufferUnavailable
    case renderFailed
    case renderStalled
}

private nonisolated enum ModeledOrganRenderingError: Error {
    case bufferUnavailable
}

private nonisolated enum PitchPipeRenderingError: Error {
    case bufferUnavailable
}

nonisolated enum CantorGuideSynthesizer {
    private static let g4Frequency = 392.0
    private static let secondsPerBeat = 0.38

    static func seconds(for event: ChantEvent, tempo: Double) -> Double {
        let safeTempo = max(0.1, tempo)
        return max(0.09, secondsPerBeat * event.durationWeight / safeTempo)
    }

    static func performance(
        for selectedEvents: [ChantEvent],
        in score: ChantScore
    ) -> [CantorGuidePerformanceEvent] {
        guard !selectedEvents.isEmpty else { return [] }

        let semantics = notationSemantics(in: score)
        return selectedEvents.enumerated().map { index, event in
            let previous = index > 0 ? selectedEvents[index - 1] : nil
            let next = index + 1 < selectedEvents.count
                ? selectedEvents[index + 1]
                : nil
            let silenceWeight = semantics.divisionAfterEvent[event.id]
                .map(silenceWeight(for:))
                ?? fallbackSilenceWeight(after: event, before: next)
            let previousSilence = previous.map {
                semantics.divisionAfterEvent[$0.id]
                    .map(silenceWeight(for:))
                    ?? fallbackSilenceWeight(after: $0, before: event)
            } ?? 0

            return CantorGuidePerformanceEvent(
                event: event,
                durationWeight: durationWeight(
                    at: index,
                    in: selectedEvents,
                    notesByEventID: semantics.notesByEventID
                ),
                followingSilenceWeight: silenceWeight,
                startsPhrase: index == 0 || previousSilence > 0,
                endsPhrase: index == selectedEvents.count - 1 || silenceWeight > 0,
                startsSyllable: previous?.syllableID != event.syllableID,
                endsSyllable: next?.syllableID != event.syllableID
            )
        }
    }

    private struct NotationSemantics {
        var notesByEventID: [String: SemanticNote] = [:]
        var divisionAfterEvent: [String: GregorianDivision] = [:]
    }

    private struct SemanticNote {
        let note: GregorianNote
        let neumeForm: GregorianNeumeForm

        var isSalicusPulse: Bool {
            note.hasIctus
                && (neumeForm == .salicus || neumeForm == .salicusFlexus)
        }
    }

    private static func notationSemantics(in score: ChantScore) -> NotationSemantics {
        let parseableGABC = score.gabc.contains("%%")
            ? score.gabc
            : "%%\(score.gabc)"
        guard let notation = try? GregorianScoreParser.parse(
            gabc: parseableGABC,
            timeline: score.timeline
        ) else {
            return NotationSemantics()
        }

        var result = NotationSemantics()
        var lastEventID: String?
        for element in notation.elements {
            switch element {
            case let .neume(neume):
                for note in neume.notes {
                    result.notesByEventID[note.id] = SemanticNote(
                        note: note,
                        neumeForm: neume.form
                    )
                    lastEventID = note.id
                }
            case let .division(division):
                if let lastEventID {
                    result.divisionAfterEvent[lastEventID] = division
                }
            case .clef, .accidental, .lyricMark, .forcedBreak:
                break
            @unknown default:
                break
            }
        }
        return result
    }

    private static func durationWeight(
        at index: Int,
        in events: [ChantEvent],
        notesByEventID: [String: SemanticNote]
    ) -> Double {
        let event = events[index]
        let semantic = notesByEventID[event.id]
        let hasMora = semantic?.note.hasMora
            ?? event.modifiers.contains(.mora)
        let hasEpisema = semantic?.note.hasEpisema
            ?? event.modifiers.contains(.episema)

        // Remove the compiler's former additive timing hints before applying
        // the contextual Solesmes-style values below. This also preserves
        // deliberately unusual fixture or generated-event weights.
        var baseline = event.durationWeight
        if event.modifiers.contains(.phraseBoundary) { baseline -= 0.4 }
        if event.modifiers.contains(.mora) { baseline -= 0.5 }
        if event.modifiers.contains(.episema) { baseline -= 0.25 }
        baseline = max(0.01, baseline)

        if hasMora {
            return max(baseline, 2)
        }

        if index + 1 < events.count {
            let next = events[index + 1]
            let nextSemantic = notesByEventID[next.id]
            let nextHasDoubleMora = (nextSemantic?.note.moraCount ?? 0) > 1
            let nextIsQuilisma = nextSemantic?.note.shape == .quilisma
                || next.modifiers.contains(.quilisma)
            if nextHasDoubleMora
                || nextIsQuilisma
                || nextSemantic?.isSalicusPulse == true {
                return max(baseline, 1.8)
            }
        }

        if hasEpisema {
            var neighboringEpisemata = 1
            if index > 0 {
                let previous = events[index - 1]
                if notesByEventID[previous.id]?.note.hasEpisema
                    ?? previous.modifiers.contains(.episema) {
                    neighboringEpisemata += 1
                }
            }
            if index + 1 < events.count {
                let next = events[index + 1]
                if notesByEventID[next.id]?.note.hasEpisema
                    ?? next.modifiers.contains(.episema) {
                    neighboringEpisemata += 1
                }
            }
            return max(baseline, 1 + 0.9 / Double(neighboringEpisemata))
        }

        return baseline
    }

    private static func silenceWeight(for division: GregorianDivision) -> Double {
        switch division {
        case .minima:
            0
        case .minor:
            1
        case .major, .final:
            2
        @unknown default:
            1
        }
    }

    private static func fallbackSilenceWeight(
        after event: ChantEvent,
        before next: ChantEvent?
    ) -> Double {
        guard event.modifiers.contains(.phraseBoundary),
              next == nil || next?.phraseID != event.phraseID else {
            return 0
        }
        return 1
    }

    static func semitoneOffset(
        for event: ChantEvent,
        clef: GABCClef = .c3
    ) -> Int {
        let eventClef = event.clef.map(GABCClef.init) ?? clef
        var semitones = eventClef.semitoneOffset(forStaffStep: event.relativePitch)
        if event.modifiers.contains(.flat),
           !eventClef.appliesDefaultFlat(to: event.relativePitch) {
            semitones -= 1
        } else if event.modifiers.contains(.natural),
                  eventClef.appliesDefaultFlat(to: event.relativePitch) {
            semitones += 1
        } else if event.modifiers.contains(.sharp) {
            semitones += eventClef.appliesDefaultFlat(to: event.relativePitch) ? 2 : 1
        }
        return semitones
    }

    static func centeredTransposition(
        for events: [ChantEvent],
        targetOffset: Int,
        clef: GABCClef = .c3
    ) -> Int {
        let offsets = events.map { semitoneOffset(for: $0, clef: clef) }
        let counts = offsets.reduce(into: [Int: Int]()) { result, offset in
            result[offset, default: 0] += 1
        }
        guard let dominantOffset = counts.max(by: { left, right in
            if left.value == right.value {
                return left.key < right.key
            }
            return left.value < right.value
        })?.key else {
            return targetOffset
        }
        return targetOffset - dominantOffset
    }

    static func frequency(
        for event: ChantEvent,
        transposition: Int,
        clef: GABCClef = .c3
    ) -> Double {
        let semitones = Double(semitoneOffset(for: event, clef: clef) + transposition)
        return g4Frequency * pow(2, semitones / 12.0)
    }

    #if DEBUG
    static func auditionBuffers(
        scholaPitch: ScholaPitch = .a,
        register: ChantRegister,
        format: AVAudioFormat
    ) throws -> [AVAudioPCMBuffer] {
        // The final seven notes repeat the opening phrase so loop joins can be
        // auditioned alongside recitation, melisma, range, and divisions.
        let pitches = [
            0, 0, 0, 2, 4, 7, 4,
            2, 0, -4, 0,
            0, 0, 0, 2, 4, 7, 4
        ]
        let events = pitches.enumerated().map { index, pitch in
            let phraseID = if index < 7 {
                "audition-phrase-1"
            } else if index < 11 {
                "audition-phrase-2"
            } else {
                "audition-phrase-1-loop"
            }
            return ChantEvent(
                id: "audition-note-\(index)",
                phraseID: phraseID,
                syllableID: (3...6).contains(index)
                    || (14...17).contains(index)
                    ? "audition-melisma"
                    : "audition-syllable-\(index)",
                syllable: "ah",
                relativePitch: pitch,
                durationWeight: index == 2 ? 2 : 1
            )
        }
        let performanceEvents = events.enumerated().map { index, event in
            let startsPhrase = index == 0 || index == 7 || index == 11
            let endsPhrase = index == 6 || index == 10
                || index == events.count - 1
            return CantorGuidePerformanceEvent(
                event: event,
                durationWeight: event.durationWeight,
                followingSilenceWeight: index == 6
                    ? 1
                    : endsPhrase ? 2 : 0,
                startsPhrase: startsPhrase,
                endsPhrase: endsPhrase,
                startsSyllable: index == 0
                    || events[index - 1].syllableID != event.syllableID,
                endsSyllable: index == events.count - 1
                    || events[index + 1].syllableID != event.syllableID
            )
        }
        guard let soundBankURL = HarpSoundBank.bundledURL else {
            throw CantorGuideAudioError.soundBankUnavailable
        }
        let renderer = try SampledHarpRenderer(
            soundBankURL: soundBankURL,
            format: format
        )
        let transposition =
            scholaPitch.semitoneOffset + register.octaveOffset
        return try performanceEvents.map {
            try renderer.render(
                performanceEvent: $0,
                tempo: 1,
                transposition: transposition,
                clef: .c3,
                register: register
            )
        }
    }
    #endif

}

#if DEBUG
nonisolated enum CantorGuideAuditionHarness {
    static func export(
        to url: URL,
        scholaPitch: ScholaPitch = .a,
        register: ChantRegister,
        sampleRate: Double = 48_000
    ) throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!
        let buffers = try CantorGuideSynthesizer.auditionBuffers(
            scholaPitch: scholaPitch,
            register: register,
            format: format
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        for buffer in buffers {
            try file.write(from: buffer)
        }
    }
}
#endif

nonisolated struct GABCClef: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case c
        case f
    }

    static let c3 = GABCClef(kind: .c, line: 3, flattensB: false)

    let kind: Kind
    let line: Int
    let flattensB: Bool

    init(kind: Kind, line: Int, flattensB: Bool = false) {
        self.kind = kind
        self.line = line
        self.flattensB = flattensB
    }

    init(_ clef: ChantClef) {
        self.init(
            kind: clef.kind == .f ? .f : .c,
            line: clef.line,
            flattensB: clef.flattensB
        )
    }

    init(gabc: String) {
        let body = gabc.split(separator: "%%", maxSplits: 1).last.map(String.init) ?? gabc
        guard let range = body.range(
            of: #"\((cb?[1-4]|f[1-4])"#,
            options: .regularExpression
        ) else {
            self = .c3
            return
        }

        let token = body[range].dropFirst()
        let isF = token.first == "f"
        let isFlatC = token.hasPrefix("cb")
        let lineCharacter = token.last
        self.init(
            kind: isF ? .f : .c,
            line: lineCharacter.flatMap { Int(String($0)) } ?? 3,
            flattensB: isFlatC
        )
    }

    func semitoneOffset(forStaffStep staffStep: Int) -> Int {
        let offset = diatonicOffsetFromC(forStaffStep: staffStep)
        let octave = Int(floor(Double(offset) / 7.0))
        let scaleIndex = offset - octave * 7
        let naturalSemitonesFromC = [0, 2, 4, 5, 7, 9, 11]
        var semitones = octave * 12 + naturalSemitonesFromC[scaleIndex]
        if flattensB, scaleIndex == 6 {
            semitones -= 1
        }
        return semitones
    }

    func appliesDefaultFlat(to staffStep: Int) -> Bool {
        guard flattensB else { return false }
        let offset = diatonicOffsetFromC(forStaffStep: staffStep)
        let octave = Int(floor(Double(offset) / 7.0))
        return offset - octave * 7 == 6
    }

    private func diatonicOffsetFromC(forStaffStep staffStep: Int) -> Int {
        // GABC `h` is Exsurge staff position 1; C/F clef lines occupy
        // positions -3, -1, 1, and 3. An F clef places C three steps lower.
        let noteStaffPosition = staffStep + 1
        let clefStaffPosition = 2 * line - 5
        let cStaffPosition = kind == .c
            ? clefStaffPosition
            : clefStaffPosition - 3
        return noteStaffPosition - cStaffPosition
    }
}
