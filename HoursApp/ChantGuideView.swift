import HoursCore
import SwiftUI

struct ChantGuideView: View {
    @Environment(ChantPlaybackController.self) private var playback
    @State private var document: ChantGuideDocument?
    @State private var loadError: String?
    @State private var selectedSectionID: String?
    @State private var showsGlossary = false
    @State private var pendingSectionID: String?

    var body: some View {
        Group {
            if let document {
                contents(document)
            } else if let loadError {
                ContentUnavailableView("Guide unavailable", systemImage: "book.closed", description: Text(loadError))
            } else {
                ProgressView("Opening guide…")
            }
        }
        .background(Color.hoursBackground)
        .navigationTitle("Guide to Chant")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard document == nil else { return }
            playback.stop()
            do { document = try await Task.detached { try ChantGuideDocument.load() }.value }
            catch { loadError = error.localizedDescription }
        }
    }

    private func contents(_ document: ChantGuideDocument) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(document.title).font(.system(.largeTitle, design: .serif))
                    Text(document.introduction).font(.system(.body, design: .serif))
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("chant-guide-introduction")
            }

            Section {
                ForEach(document.sections) { section in
                    Button {
                        selectedSectionID = section.id
                    } label: {
                        HStack(spacing: 16) {
                            Text(section.title)
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityHint("Opens this chant lesson")
                    .accessibilityIdentifier("chant-guide-lesson-\(section.id)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("chant-guide-topics")
        .navigationDestination(item: $selectedSectionID) { id in
            if let section = document.sections.first(where: { $0.id == id }) {
                ChantGuideLessonView(document: document, section: section)
                    .id(section.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Glossary", systemImage: "character.book.closed") { showsGlossary = true }
                    .accessibilityIdentifier("chant-guide-glossary")
            }
        }
        .sheet(isPresented: $showsGlossary, onDismiss: {
            if let pendingSectionID {
                selectedSectionID = pendingSectionID
                self.pendingSectionID = nil
            }
        }) {
            NavigationStack {
                List(document.glossary) { term in
                    Button {
                        pendingSectionID = term.sectionID
                        showsGlossary = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(term.term).font(.headline)
                            Text(term.definition).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Chant glossary")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsGlossary = false } } }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

private struct ChantGuideLessonView: View {
    @Environment(ChantPlaybackController.self) private var playback
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let document: ChantGuideDocument
    let section: ChantGuideSection
    @State private var selectedID: String?
    @State private var variants: [String: String] = [
        "clef-staff-positions": "guide-clef-staff-positions-c4"
    ]
    @State private var suppressed = false
    @State private var hasPresentedControls = false
    @State private var frames: [String: CGRect] = [:]
    @State private var viewport = CGRect.zero
    @State private var controlsFrame = CGRect.zero
    @State private var scrollPosition = ScrollPosition()
    @State private var isScrolling = false

    var body: some View {
        reader(document)
        .background(Color.hoursBackground)
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onAppear { playback.stop() }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.stop() }
        }
    }

    private func reader(_ document: ChantGuideDocument) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.system(.largeTitle, design: .serif))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("chant-guide-lesson-title")
                        Text("Liber Usualis · \(section.source)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .id(section.id)
                    .guideFrame(section.id)

                    ForEach(section.blocks) { block in
                        blockView(block, document: document, width: min(geometry.size.width, 760) - 48)
                            .id(block.id)
                            .guideFrame(block.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("chant-guide-reader")
            .scrollPosition($scrollPosition)
            .onScrollPhaseChange { _, phase in
                isScrolling = phase != .idle
                if phase == .idle { updateTarget(document) }
            }
            .onPreferenceChange(ChantGuideFrames.self) {
                frames = $0
                if playback.isPlaying, let selectedID,
                   let block = section.blocks.first(where: { $0.exampleID == selectedID }),
                   (frames[block.id]?.intersection(readingViewport).height ?? 0) <= 1 {
                    playback.stop()
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
            .task(id: frames) {
                // Geometry also changes after asynchronous engraving or text reflow.
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, !isScrolling else { return }
                updateTarget(document)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !suppressed, hasPresentedControls {
                    Group {
                        if let example = selectedExample(document) {
                            PlaybackControlsView(score: variant(example).score, onClose: closeControls,
                                                 usesCompactPresentation: true)
                        } else {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Cantor guide").font(.caption.weight(.semibold))
                                    Text("Scroll to a musical example to listen.").font(.callout)
                                }
                                Spacer()
                                Button(action: closeControls) {
                                    Image(systemName: "xmark.circle.fill").font(.title2)
                                }
                                .accessibilityLabel("Close cantor guide")
                                .accessibilityIdentifier("cantor-close")
                            }
                            .padding(.horizontal)
                            .frame(height: max(110, controlsFrame.height))
                            .background(.regularMaterial)
                        }
                    }
                    .frame(maxWidth: 760)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { controlsFrame = $0 }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chant-guide-controls")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start from beginning", systemImage: "arrow.up.to.line") {
                        playback.stop()
                        scrollPosition.scrollTo(edge: .top)
                    }
                    .accessibilityIdentifier("chant-guide-start")
                }
            }
            .task { updateTarget(document) }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ChantGuideBlock, document: ChantGuideDocument, width: CGFloat) -> some View {
        switch block.kind {
        case .prose:
            VStack(alignment: .leading, spacing: 10) {
                if let title = block.title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
                Text(block.text ?? "").font(.system(.body, design: .serif)).lineSpacing(4).textSelection(.enabled)
            }
        case .pronunciation:
            DisclosureGroup {
                Text(block.detail ?? "").font(.system(.body, design: .serif)).padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title ?? "Pronunciation").font(.headline)
                    Text(block.text ?? "").foregroundStyle(.secondary)
                }
            }
            .tint(Color.hoursTodayAccent)
        case .example:
            if let id = block.exampleID, let example = document.example(id) {
                ChantGuideExampleView(
                    example: example, variant: variant(example), width: max(160, width),
                    preparationViewport: readingViewport.insetBy(dx: 0, dy: -viewport.height),
                    isSelected: selectedID == id,
                    onVariant: { variantID in
                        playback.stop()
                        variants[id] = variantID
                        select(example)
                    },
                    onPlay: { eventID in
                        suppressed = false
                        select(example)
                        playback.play(score: variant(example).score, fromEventID: eventID)
                    },
                    onPlayNote: { eventID in
                        suppressed = false
                        select(example)
                        playback.playNote(score: variant(example).score, eventID: eventID)
                    }
                )
            }
        }
    }

    private func selectedExample(_ document: ChantGuideDocument) -> ChantGuideExample? {
        selectedID.flatMap(document.example)
    }

    private func variant(_ example: ChantGuideExample) -> ChantGuideVariant {
        example.variants.first { $0.id == variants[example.id] } ?? example.variants[0]
    }

    private func select(_ example: ChantGuideExample) {
        hasPresentedControls = true
        selectedID = example.id
        playback.prepare(score: variant(example).score, pitchReference: example.pitchReference)
    }

    private func updateTarget(_ document: ChantGuideDocument) {
        guard scenePhase == .active else { return }
        let exampleFrames = Dictionary(uniqueKeysWithValues: section.blocks.compactMap { block -> (String, CGRect)? in
            guard let id = block.exampleID, let frame = frames[block.id] else { return nil }
            return (id, frame)
        })
        let target = ChantGuideViewport.target(frames: exampleFrames, viewport: readingViewport,
                                              playingID: playback.isPlaying ? selectedID : nil)
        guard target != selectedID else { return }
        playback.stop()
        selectedID = target
        if let target, let example = document.example(target) { select(example) }
    }

    private var readingViewport: CGRect {
        guard !suppressed, hasPresentedControls, controlsFrame.height > 0 else { return viewport }
        return CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width,
                      height: max(0, min(viewport.maxY, controlsFrame.minY) - viewport.minY))
    }

    private func closeControls() {
        playback.stop()
        suppressed = true
    }
}

private struct ChantGuideFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func guideFrame(_ id: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: ChantGuideFrames.self, value: [id: geometry.frame(in: .global)])
        })
    }
}
