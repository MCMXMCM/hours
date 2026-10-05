import HoursCore
import SwiftUI

struct PlaybackControlsView: View {
    let score: ChantScore
    let onClose: () -> Void
    var usesCompactPresentation = false
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @GestureState private var dismissalOffset: CGFloat = 0
    @State private var showsOptions = false

    var body: some View {
        @Bindable var playback = playback

        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.55))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 9)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cantor guide")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(CantorGuideTitle.text(for: score))
                            .font(.system(.headline, design: .serif))
                            .lineLimit(1)
                    }
                    Spacer()
                    if usesCompactPresentation {
                        Button { showsOptions = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cantor guide options")
                        .accessibilityIdentifier("cantor-options")
                    }
                    Button {
                        playback.toggle(score: score)
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 35))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playback.isPlaying ? "Pause cantor guide" : "Play cantor guide")
                    .accessibilityIdentifier("cantor-play")

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close cantor guide")
                    .accessibilityIdentifier("cantor-close")
                    .appTourTarget(.cantorClose)
                }

                if !usesCompactPresentation {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            tempoControl(playback: playback, tempo: $playback.tempo)

                            Divider().frame(height: 20)

                            scholaPitchControl(scholaPitch: $playback.scholaPitch)
                            registerControl(register: $playback.chantRegister)
                            soundControl(sound: $playback.guideSound)
                            loopControl(playback: playback, loopsPhrase: $playback.loopsPhrase)
                        }

                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                tempoControl(playback: playback, tempo: $playback.tempo)
                            }
                            HStack {
                                scholaPitchControl(scholaPitch: $playback.scholaPitch)
                                Spacer(minLength: 12)
                                registerControl(register: $playback.chantRegister)
                                Spacer(minLength: 12)
                                soundControl(sound: $playback.guideSound)
                                Spacer(minLength: 12)
                                loopControl(playback: playback, loopsPhrase: $playback.loopsPhrase)
                            }
                        }
                    }
                }

                if let errorMessage = playback.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("cantor-playback-error")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .contentShape(.rect)
        .offset(y: dismissalOffset)
        .simultaneousGesture(dismissalGesture)
        .animation(.interactiveSpring, value: dismissalOffset)
        .accessibilityAction(.escape, onClose)
        .onChange(of: playback.tempo) { playback.restartIfPlaying(score: score) }
        .onChange(of: playback.loopsPhrase) { playback.restartIfPlaying(score: score) }
        .onChange(of: playback.scholaPitch) { _, pitch in
            tour.receive(.scholaPitchChanged(pitch))
        }
        .sheet(isPresented: $showsOptions) {
            NavigationStack {
                Form {
                    Section("Tempo") {
                        HStack { tempoControl(playback: playback, tempo: $playback.tempo) }
                    }
                    Section("Voice") {
                        HStack { Text("Schola pitch"); Spacer(); scholaPitchControl(scholaPitch: $playback.scholaPitch) }
                        HStack { Text("Register"); Spacer(); registerControl(register: $playback.chantRegister) }
                        HStack { Text("Sound"); Spacer(); soundControl(sound: $playback.guideSound) }
                    }
                }
                .navigationTitle("Cantor guide options")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsOptions = false }
                    }
                }
            }
        }
    }

    private var dismissalGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dismissalOffset) { value, offset, _ in
                let translation = value.translation
                guard translation.height > abs(translation.width) else {
                    return
                }
                offset = max(0, translation.height)
            }
            .onEnded { value in
                guard CantorGuideDismissal.shouldDismiss(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) else {
                    return
                }
                onClose()
            }
    }

    private func tempoControl(
        playback: ChantPlaybackController,
        tempo: Binding<Double>
    ) -> some View {
        Group {
            Label("Tempo", systemImage: "metronome")
                .font(.caption)
                .fixedSize()
            Slider(value: tempo, in: 0.65...1.45, step: 0.05)
                .accessibilityIdentifier("tempo-slider")
            Text("\(Int(playback.tempo * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func scholaPitchControl(
        scholaPitch: Binding<ScholaPitch>
    ) -> some View {
        Picker("Schola pitch", selection: scholaPitch) {
            ForEach(ScholaPitch.allCases) { pitch in
                Text(pitch.displayName).tag(pitch)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
        .fixedSize()
        .accessibilityValue(scholaPitch.wrappedValue.displayName)
        .accessibilityIdentifier("cantor-schola-pitch")
        .appTourTarget(.cantorPitch)
    }

    private func soundControl(
        sound: Binding<CantorGuideSound>
    ) -> some View {
        Picker("Sound", selection: sound) {
            ForEach(CantorGuideSound.allCases) { choice in
                Text(choice.displayName).tag(choice)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
        .fixedSize()
        .accessibilityValue(sound.wrappedValue.displayName)
        .accessibilityIdentifier("cantor-sound")
    }

    private func registerControl(
        register: Binding<ChantRegister>
    ) -> some View {
        Picker("Register", selection: register) {
            ForEach(ChantRegister.allCases) { choice in
                Text(choice.displayName).tag(choice)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
        .fixedSize()
        .accessibilityValue(register.wrappedValue.displayName)
        .accessibilityIdentifier("cantor-register")
    }

    private func loopControl(
        playback: ChantPlaybackController,
        loopsPhrase: Binding<Bool>
    ) -> some View {
        Toggle(isOn: loopsPhrase) {
            Label("Loop phrase", systemImage: "repeat")
        }
        .toggleStyle(.button)
        .font(.caption)
        .fixedSize()
    }
}

enum CantorGuideTitle {
    static func text(for score: ChantScore) -> String {
        guard isStandaloneVersicleOrResponse(score.incipit),
              let parsedScore = try? GregorianScoreParser.parse(
                  gabc: score.gabc,
                  timeline: score.timeline
              ) else {
            return score.incipit
        }

        var line = ""
        for element in parsedScore.elements {
            switch element {
            case let .lyricMark(mark):
                guard !isStandaloneVersicleOrResponse(mark.text) else {
                    continue
                }
                append(
                    mark.text,
                    startsWord: mark.startsWord,
                    to: &line
                )
            case let .neume(neume):
                append(
                    neume.lyric,
                    startsWord: neume.startsWord,
                    to: &line
                )
            case .clef, .accidental, .division, .forcedBreak:
                continue
            @unknown default:
                continue
            }
        }

        return line.isEmpty ? score.incipit : line
    }

    private static func append(
        _ text: String,
        startsWord: Bool,
        to line: inout String
    ) {
        guard !text.isEmpty else { return }
        if startsWord, !line.isEmpty {
            line.append(" ")
        }
        line.append(text)
    }

    private static func isStandaloneVersicleOrResponse(
        _ value: String
    ) -> Bool {
        let marker = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return [
            "V/", "V/.", "R/", "R/.",
            "℣", "℣.", "℟", "℟."
        ].contains(marker)
    }
}

enum CantorGuideDismissal {
    static func shouldDismiss(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        translation.height > abs(translation.width)
            && (
                translation.height > 84
                    || predictedEndTranslation.height > 150
            )
    }
}
