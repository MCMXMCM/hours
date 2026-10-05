import HoursCore
import SwiftUI

struct ChantGuideExampleView: View {
    let example: ChantGuideExample
    let variant: ChantGuideVariant
    let width: CGFloat
    let preparationViewport: CGRect
    let isSelected: Bool
    let onVariant: (String) -> Void
    let onPlay: (String?) -> Void
    let onPlayNote: (String) -> Void
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: DisplayedGuideStave?
    @State private var explores = false
    @State private var selectedAnnotation: ChantGuideAnnotation?
    @State private var selectedEventID: String?
    @State private var isNearby = false

    private var preparationID: String { "\(variant.id):\(Int(width)):\(dynamicTypeSize):\(isNearby)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(example.title).font(.system(.headline, design: .serif))
                Spacer(minLength: 12)
                Button {
                    if isSelected, playback.isPlaying { playback.stop() }
                    else { onPlay(nil) }
                } label: {
                    Label(isSelected && playback.isPlaying ? "Pause" : "Play",
                          systemImage: isSelected && playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .labelStyle(.iconOnly).font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isSelected && playback.isPlaying ? "Pause" : "Play") \(example.title)")
                .accessibilityIdentifier("guide-play-\(example.id)")
            }
            if example.caption != variant.explanation {
                Text(example.caption).font(.callout).foregroundStyle(.secondary)
            }

            if example.variants.count > 1 {
                if example.id == "modal-formulas" {
                    Text("Rest On").font(.callout.weight(.medium))
                }
                variantSelector
            }
            if let formula = variant.formula {
                ChantGuideFormulaView(notes: formula)
            }
            stave

            Text(variant.explanation).font(.system(.body, design: .serif)).lineSpacing(3)
            DisclosureGroup(isExpanded: $explores) {
                exploration.padding(.top, 12)
            } label: { Text("Explore notation").font(.callout.weight(.medium)) }
            .accessibilityIdentifier("guide-explore-\(example.id)")
            Text(example.source).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(Color.hoursTodayAccent.opacity(0.35)).frame(height: 1) }
        .tint(Color.hoursTodayAccent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guide-example-\(example.id)")
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.frame(in: .global).intersects(preparationViewport)
        } action: { isNearby = $0 }
        .task(id: preparationID) {
            guard isNearby else { return }
            selectedEventID = nil
            selectedAnnotation = nil
            do {
                let lyricScale = GregorianScoreView.lyricScale(for: dynamicTypeSize)
                let ready = try await GregorianLayoutCache.shared.preparedScore(
                    score: variant.score, width: width,
                    metrics: GregorianLayoutMetrics(
                        notationScale: max(1, min(GregorianLayoutMetrics.maximumNotationScale, lyricScale)),
                        lyricScale: lyricScale
                    )
                )
                guard !Task.isCancelled else { return }
                show(DisplayedGuideStave(score: variant.score, preparation: .ready(ready)))
            } catch {
                guard !Task.isCancelled else { return }
                show(DisplayedGuideStave(score: variant.score, preparation: .failed(error.localizedDescription)))
            }
        }
    }

    private var staveHeight: CGFloat {
        displayed.map { $0.preparation.height + (explores ? 20 : 0) } ?? 140
    }

    private func show(_ next: DisplayedGuideStave) {
        let shouldAnimate = !reduceMotion && displayed?.score.id != next.score.id
        withAnimation(shouldAnimate ? .easeInOut(duration: 0.28) : nil) {
            displayed = next
        }
    }

    private var stave: some View {
        ZStack(alignment: .topLeading) {
            if let displayed {
                ChantGuideStaveLayer(
                    score: displayed.score,
                    preparation: displayed.preparation,
                    highlightedEventID: isSelected && playback.preparedScoreID == displayed.score.id
                        ? playback.currentEventID : nil,
                    explores: explores,
                    selectedIDs: selectedAnnotation?.eventIDs ?? selectedEventID.map { [$0] } ?? [],
                    onTapEvent: { onPlay($0) }
                )
                .id(displayed.score.id)
                .transition(.opacity)
            } else {
                ProgressView("Preparing example…")
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: staveHeight, maxHeight: staveHeight, alignment: .topLeading)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: displayed?.score.id)
    }

    // Display staff positions from top to bottom without changing the score's
    // first variant, which also supplies the comparison's pitch reference.
    private var variantChoices: [ChantGuideVariant] {
        example.id == "clef-staff-positions" ? Array(example.variants.reversed()) : example.variants
    }

    @ViewBuilder
    private var variantSelector: some View {
        if example.variants.count <= 3 || example.id == "modal-formulas" {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    ForEach(variantChoices) { choice in
                        Button { onVariant(choice.id) } label: {
                            Text(tabTitle(for: choice))
                                .font(.subheadline)
                                .foregroundStyle(choice.id == variant.id ? Color.hoursTodayAccent : Color.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(choice.id == variant.id ? .isSelected : [])
                        .accessibilityIdentifier("guide-variant-tab-\(choice.id)")
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(example.id == "modal-formulas" ? "Rest On" : "Example version")

                variantMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            variantMenu
        }
    }

    private var variantMenu: some View {
        Picker("Example version", selection: Binding(get: { variant.id }, set: { onVariant($0) })) {
            ForEach(variantChoices) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("guide-variant-\(example.id)")
    }

    private func tabTitle(for choice: ChantGuideVariant) -> String {
        if example.id == "modal-formulas", choice.title.hasPrefix("Rest on ") {
            return String(choice.title.dropFirst("Rest on ".count))
        }
        if example.id == "clef-staff-positions" {
            switch choice.score.timeline.events.first?.clef?.line {
            case 4: return "Fourth line"
            case 3: return "Third line"
            case 2: return "Second line"
            default: break
            }
        }
        return choice.title
    }

    private var exploration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Singing order · select a note to hear it and locate it on the staff")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(variant.score.timeline.events.enumerated()), id: \.element.id) { index, event in
                    Button {
                        selectedEventID = event.id
                        selectedAnnotation = nil
                        onPlayNote(event.id)
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(index + 1)").font(.caption.monospacedDigit())
                            Text(ChantGuideSolfege.name(event, score: variant.score)).font(.callout.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selectedEventID == event.id ? Color.hoursTodayAccent.opacity(0.16) : Color.secondary.opacity(0.07), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Note \(index + 1), \(ChantGuideSolfege.name(event, score: variant.score)), \(event.syllable)")
                    .accessibilityHint("Plays this note and highlights it on the staff")
                }
            }
            ForEach(variant.annotations) { annotation in
                Button {
                    selectedAnnotation = selectedAnnotation?.id == annotation.id ? nil : annotation
                    selectedEventID = nil
                } label: {
                    Label(annotation.label, systemImage: selectedAnnotation?.id == annotation.id ? "minus.circle" : "plus.circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                if selectedAnnotation?.id == annotation.id {
                    Text(annotation.explanation).font(.callout)
                }
            }
        }
    }
}

private struct DisplayedGuideStave {
    let score: ChantScore
    let preparation: GregorianScorePreparation
}

private struct ChantGuideStaveLayer: View {
    let score: ChantScore
    let preparation: GregorianScorePreparation
    let highlightedEventID: String?
    let explores: Bool
    let selectedIDs: [String]
    let onTapEvent: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            GregorianScoreView(
                score: score, preparation: preparation,
                highlightedEventID: highlightedEventID,
                onTapEvent: onTapEvent, onActiveNeumeFrameChange: { _ in }
            )
            if explores, case let .ready(prepared) = preparation {
                annotationOverlay(prepared.layout)
            }
        }
        .padding(.top, explores ? 20 : 0)
        .compositingGroup()
    }

    private func annotationOverlay(_ layout: GregorianLayout) -> some View {
        Canvas { context, _ in
            let placements = layout.events.filter { selectedIDs.contains($0.eventID) }
            for placement in placements {
                context.stroke(Path(roundedRect: placement.frame.insetBy(dx: -3, dy: -3), cornerRadius: 3),
                               with: .color(.hoursTodayAccent), lineWidth: 1.5)
            }
            // Split brackets at actual system breaks; annotation geometry never enters the timeline.
            for staff in layout.staffs {
                let onLine = placements.filter { $0.lineIndex == staff.index }
                guard onLine.count > 1,
                      let left = onLine.map(\.frame.minX).min(),
                      let right = onLine.map(\.frame.maxX).max() else { continue }
                let y = min(staff.frame.minY - 9, (onLine.map(\.frame.minY).min() ?? 0) - 9)
                var bracket = Path()
                bracket.move(to: CGPoint(x: left, y: y + 4))
                bracket.addLine(to: CGPoint(x: left, y: y))
                bracket.addLine(to: CGPoint(x: right, y: y))
                bracket.addLine(to: CGPoint(x: right, y: y + 4))
                context.stroke(bracket, with: .color(.hoursTodayAccent), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

nonisolated enum ChantGuideSolfege {
    static func name(_ event: ChantEvent, score: ChantScore) -> String {
        let clef = event.clef.map(GABCClef.init) ?? GABCClef(gabc: score.gabc)
        let step = event.relativePitch + 1 - (2 * clef.line - 5) + (clef.kind == .f ? 3 : 0)
        let index = (step % 7 + 7) % 7
        let flat = event.modifiers.contains(.flat) || (clef.flattensB && index == 6 && !event.modifiers.contains(.natural))
        return ["Do", "Re", "Mi", "Fa", "Sol", "La", "Ti"][index] + (flat ? "♭" : "")
    }
}

private struct ChantGuideFormulaView: View {
    let notes: [ChantGuideFormulaNote]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Formula · hollow notes are used only when needed")
                .font(.caption).foregroundStyle(.secondary)
            Canvas { context, size in
                for line in 0..<4 {
                    var path = Path()
                    path.move(to: CGPoint(x: 8, y: 18 + line * 12))
                    path.addLine(to: CGPoint(x: size.width - 8, y: CGFloat(18 + line * 12)))
                    context.stroke(path, with: .color(.secondary), lineWidth: 0.8)
                }
                for (index, note) in notes.enumerated() {
                    let x = 20 + CGFloat(index) * (size.width - 40) / CGFloat(max(1, notes.count - 1))
                    let rect = CGRect(x: x - 4, y: 50 - CGFloat(note.step) * 6, width: 8, height: 8)
                    if note.optional { context.stroke(Path(rect), with: .color(.primary), lineWidth: 1.5) }
                    else { context.fill(Path(rect), with: .color(.primary)) }
                    context.draw(Text(note.label).font(.system(size: 11)), at: CGPoint(x: x, y: 78))
                }
            }
            .frame(height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notes.map { "\($0.label)\($0.optional ? ", additional note" : "")" }.joined(separator: "; "))
        }
    }
}
