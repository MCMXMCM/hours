import HoursCore
import SwiftUI

/// The cantor guide, floating in glass over the foot of the page while a
/// chant is sung: what is being sung, play and pause, and close. How it
/// sings (its tempo, pitch, register, and sound, and whether it repeats a
/// phrase) is seldom changed, so those wait in a sheet behind the options
/// button. Drawn down, or closed, the guide stops.
struct PlaybackControlsView: View {
    let score: ChantScore
    let onClose: () -> Void
    /// Whether the guide offers to repeat the phrase it starts from. The
    /// Guide to Chant's short examples have no phrase to repeat.
    var offersPhraseLoop = true
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @GestureState private var dismissalOffset: CGFloat = 0
    @State private var showsOptions = false

    var body: some View {
        let title = CantorGuideTitle.text(for: score)

        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Cantor guide, \(title)")

                Button(action: openOptions) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 19))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Cantor guide options")
                .accessibilityIdentifier("cantor-options")
                .appTourTarget(.cantorOptions)

                Button {
                    playback.toggle(score: score)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 35))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(playback.isPlaying ? "Pause cantor guide" : "Play cantor guide")
                .accessibilityIdentifier("cantor-play")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Close cantor guide")
                .accessibilityIdentifier("cantor-close")
                .appTourTarget(.cantorClose)
            }
            .buttonStyle(.plain)

            if let errorMessage = playback.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("cantor-playback-error")
            }
        }
        .cantorGuideBubble()
        .offset(y: dismissalOffset)
        .simultaneousGesture(dismissalGesture)
        .animation(.interactiveSpring, value: dismissalOffset)
        .accessibilityAction(.escape, onClose)
        .onChange(of: playback.tempo) { playback.restartIfPlaying(score: score) }
        .onChange(of: playback.loopsPhrase) { playback.restartIfPlaying(score: score) }
        .onChange(of: playback.scholaPitch) { _, pitch in
            tour.receive(.scholaPitchChanged(pitch))
        }
        .sheet(
            isPresented: $showsOptions,
            onDismiss: {
                tour.receive(.cantorOptionsClosed)
            }
        ) {
            CantorGuideOptionsView(offersPhraseLoop: offersPhraseLoop) {
                showsOptions = false
            }
            .presentationDetents(optionsDetents)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(
                tour.isActive && tour.step != .closeCantorOptions
            )
            .appTourOverlayHost(
                .reader,
                during: .only([.changeCantorPitch, .closeCantorOptions])
            )
            .environment(playback)
            .environment(tour)
        }
    }

    /// The options open at half height on a phone. A wide screen's card
    /// would cut them off at half height, and the tour's spotlight is placed
    /// amiss in a sheet floated at half height, so both open at full height.
    private var optionsDetents: Set<PresentationDetent> {
        horizontalSizeClass == .regular || tour.isActive
            ? [.large]
            : [.medium, .large]
    }

    /// Opens the options; while the tour is under way, only at its step
    /// that asks for them.
    private func openOptions() {
        guard !tour.isActive || tour.step == .openCantorOptions else { return }
        showsOptions = true
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
}

/// How the cantor guide sings, in a sheet over the page: its tempo, its
/// pitch, register, and sound, and whether it repeats a phrase.
private struct CantorGuideOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(AppTourCoordinator.self) private var tour
    let offersPhraseLoop: Bool
    let onClose: () -> Void

    var body: some View {
        @Bindable var playback = playback

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "metronome")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(value: $playback.tempo, in: 0.65...1.45, step: 0.05)
                            .accessibilityLabel("Tempo")
                            .accessibilityValue("\(tempoPercent) percent")
                            .accessibilityIdentifier("tempo-slider")
                        Text("\(tempoPercent)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                } header: {
                    Text("Tempo")
                } footer: {
                    Text("A slower tempo helps in learning a new melody.")
                }

                Section {
                    Picker("Schola pitch", selection: $playback.scholaPitch) {
                        ForEach(ScholaPitch.allCases) { pitch in
                            Text(pitch.displayName).tag(pitch)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityValue(playback.scholaPitch.displayName)
                    .accessibilityIdentifier("cantor-schola-pitch")
                    .appTourTarget(.cantorPitch)

                    Picker("Register", selection: $playback.chantRegister) {
                        ForEach(ChantRegister.allCases) { register in
                            Text(register.displayName).tag(register)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityValue(playback.chantRegister.displayName)
                    .accessibilityIdentifier("cantor-register")

                    Picker("Sound", selection: $playback.guideSound) {
                        ForEach(CantorGuideSound.allCases) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityValue(playback.guideSound.displayName)
                    .accessibilityIdentifier("cantor-sound")
                } header: {
                    Text("Voice")
                } footer: {
                    Text(
                        "The reciting tone is placed at the selected schola "
                            + "pitch and register."
                    )
                }

                if offersPhraseLoop {
                    Section {
                        Toggle(isOn: $playback.loopsPhrase) {
                            Label("Loop phrase", systemImage: "repeat")
                        }
                        .accessibilityIdentifier("cantor-loop-phrase")
                    } footer: {
                        Text(
                            "Repeats the phrase the guide starts from until "
                                + "it is paused."
                        )
                    }
                }
            }
            .navigationTitle("Cantor guide options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !tour.isActive || tour.step == .closeCantorOptions {
                        SheetCloseButton(
                            accessibilityLabel: "Close Cantor Guide Options",
                            accessibilityIdentifier: "cantor-options-close",
                            appTourTarget: .cantorOptionsClose,
                            action: closeOptions
                        )
                    }
                }
            }
        }
        .onAppear {
            tour.receive(.cantorOptionsOpened)
        }
    }

    private var tempoPercent: Int {
        Int((playback.tempo * 100).rounded())
    }

    private func closeOptions() {
        if tour.isActive {
            guard tour.step == .closeCantorOptions else { return }
        }
        onClose()
        dismiss()
    }
}

extension View {
    /// The cantor guide's glass, floating clear of the page's edges.
    func cantorGuideBubble() -> some View {
        padding(.leading, 20)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
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
